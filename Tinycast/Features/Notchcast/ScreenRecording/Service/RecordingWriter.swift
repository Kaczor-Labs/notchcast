// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder writer: the master file, one track per sound source.

import AVFoundation
import CoreMedia
import VideoToolbox
import os

/// Unchecked: every call between `init` and `finish` runs on the session queue, drained before `finish`.
final class RecordingWriter: @unchecked Sendable {
    enum Kind: Sendable { case video, systemAudio, microphone }

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var systemAudioConverter: AVAudioConverter?
    private var microphoneConverter: AVAudioConverter?
    private var origin = CMTime.invalid
    private var lastVideoSample: CMSampleBuffer?
    private var lastVideoTime = CMTime.zero
    private var failed = false
    private(set) var videoFrameCount = 0

    init(url: URL, width: Int, height: Int, codec: RecordingOptions.Codec, systemAudio: Bool, microphone: Bool) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Fragments keep a recording that outlives a crash readable.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        var settings = Self.videoSettings(width: width, height: height, codec: .h264)
        if codec == .hevc {
            let hevc = Self.videoSettings(width: width, height: height, codec: .hevc)
            if writer.canApply(outputSettings: hevc, forMediaType: .video), Self.hevcEncodes(width: width, height: height) {
                settings = hevc
            }
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw RecordingTarget.Failure.captureFailed
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecordingTarget.Failure.captureFailed }
        writer.add(videoInput)
        self.writer = writer
        self.videoInput = videoInput
        systemAudioInput = systemAudio ? Self.addAudioInput(to: writer) : nil
        microphoneInput = microphone ? Self.addAudioInput(to: writer) : nil
    }

    private static func addAudioInput(to writer: AVAssetWriter) -> AVAssetWriterInput? {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        return input
    }

    /// `canApply` accepts HEVC sizes some encoders then reject on the first frame, so one frame is encoded.
    static func hevcEncodes(width: Int, height: Int) -> Bool {
        var session: VTCompressionSession?
        guard VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session) == noErr,
            let session
        else { return false }
        defer { VTCompressionSessionInvalidate(session) }
        var frame: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &frame) == noErr, let frame
        else { return false }
        let produced = OSAllocatedUnfairLock(initialState: false)
        guard VTCompressionSessionEncodeFrame(
            session, imageBuffer: frame, presentationTimeStamp: .zero, duration: .invalid, frameProperties: nil,
            infoFlagsOut: nil,
            outputHandler: { status, _, sample in
                let encoded = status == noErr && sample != nil
                produced.withLock { $0 = encoded }
            }) == noErr,
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) == noErr
        else { return false }
        return produced.withLock { $0 }
    }

    private static func videoSettings(width: Int, height: Int, codec: AVVideoCodecType) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: RecordingEncoding.averageBitRate(width: width, height: height),
            AVVideoExpectedSourceFrameRateKey: RecordingEncoding.frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: RecordingEncoding.keyframeSeconds,
            // Screen content gains little from reordering, and a file without B-frames cuts cleanly.
            AVVideoAllowFrameReorderingKey: false,
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    private static var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
    }

    func start() -> Bool { writer.startWriting() }

    /// The file's zero is the host time the capture was asked to start at.
    func beginSession(at time: CMTime) {
        guard !origin.isNumeric, time.isNumeric else { return }
        origin = time
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ sampleBuffer: CMSampleBuffer, kind: Kind) {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard !failed, origin.isNumeric, presentation.isNumeric, presentation >= origin else { return }
        let shifted = presentation - origin
        switch kind {
        case .video:
            // The first image is held over startup latency; later stamps keep sound aligned.
            let time = videoFrameCount == 0 ? CMTime.zero : shifted
            guard videoInput.isReadyForMoreMediaData,
                let retimed = RecordingSampleTiming.retimed(sampleBuffer, to: time)
            else { return }
            guard videoInput.append(retimed) else {
                failed = true
                return
            }
            videoFrameCount += 1
            lastVideoSample = sampleBuffer
            lastVideoTime = time
        case .systemAudio:
            append(sampleBuffer, to: systemAudioInput, at: shifted, converter: &systemAudioConverter)
        case .microphone:
            append(sampleBuffer, to: microphoneInput, at: shifted, converter: &microphoneConverter)
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?, at time: CMTime,
                        converter: inout AVAudioConverter?) {
        guard let input, input.isReadyForMoreMediaData,
            let interleaved = RecordingAudioSample.interleaved(sampleBuffer, converter: &converter),
            let retimed = RecordingSampleTiming.retimed(interleaved, to: time)
        else { return }
        if !input.append(retimed) { failed = true }
    }

    /// The last frame is written once more at the stop, so a still screen keeps its length.
    func finish(at end: CMTime) async -> Bool {
        guard origin.isNumeric, !failed, videoFrameCount > 0 else {
            cancel()
            return false
        }
        let length = end - origin
        if let lastVideoSample, length > lastVideoTime {
            if videoInput.isReadyForMoreMediaData,
                let tail = RecordingSampleTiming.retimed(lastVideoSample, to: length) {
                videoInput.append(tail)
            }
            writer.endSession(atSourceTime: length)
        }
        lastVideoSample = nil
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }

    func cancel() {
        lastVideoSample = nil
        if writer.status == .writing { writer.cancelWriting() }
    }
}
