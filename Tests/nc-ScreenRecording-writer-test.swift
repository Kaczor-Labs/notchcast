// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingSampleTiming.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingAudioSample.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingWriter.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingExporter.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingCaptureEngine.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingMicrophone.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingCapture.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift

import AVFoundation
import CoreMedia
import Foundation

// The capture engine, microphone and session are compiled here but never started: no screen is recorded.

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-ScreenRecording-writer-test.\(UUID())")
/// Any host time works as the file's zero; the writer only subtracts it.
let origin = CMTime(value: 5_000, timescale: 1)

func videoSample(at seconds: Double, shade: UInt8) -> CMSampleBuffer {
    var created: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
    precondition(CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, attributes, &created) == kCVReturnSuccess)
    let pixels = created!
    CVPixelBufferLockBaseAddress(pixels, [])
    memset(CVPixelBufferGetBaseAddress(pixels), Int32(shade), CVPixelBufferGetDataSize(pixels))
    CVPixelBufferUnlockBaseAddress(pixels, [])
    var format: CMVideoFormatDescription?
    precondition(CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format) == noErr)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 10),
        presentationTimeStamp: origin + CMTime(seconds: seconds, preferredTimescale: 600), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    precondition(CMSampleBufferCreateReadyWithImageBuffer(
        allocator: nil, imageBuffer: pixels, formatDescription: format!, sampleTiming: &timing,
        sampleBufferOut: &sample) == noErr)
    return sample!
}

/// A tenth of a second of a quiet tone, planar as ScreenCaptureKit delivers it unless asked interleaved.
func audioSample(at seconds: Double, interleaved: Bool = false) -> CMSampleBuffer {
    let frames = 4_800
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    pcm.frameLength = AVAudioFrameCount(frames)
    for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
        let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
        for index in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
            samples[index] = sinf(Float(index) * 0.05) * 0.2
        }
    }
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: origin + CMTime(seconds: seconds, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    precondition(CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
        formatDescription: format.formatDescription, sampleCount: frames, sampleTimingEntryCount: 1,
        sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
    precondition(CMSampleBufferSetDataBufferFromAudioBufferList(
        sample!, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0, bufferList: pcm.audioBufferList) == noErr)
    return sample!
}

func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

func names(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

/// True for a file with one picture track and one sound track.
func hasPictureAndSound(_ url: URL) async -> Bool {
    let asset = AVURLAsset(url: url)
    let video = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
    return video.count == 1 && audio.count == 1
}

func seconds(_ url: URL) async -> TimeInterval { (try? await RecordingExporter.duration(url)) ?? -1 }

@main
@MainActor
enum ScreenRecordingWriterTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        samples()
        await recordTrimSave()
        await emptyAndHEVC()
        print("\(checks) screen recording writer checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func samples() {
        let frame = videoSample(at: 1, shade: 40)
        let moved = RecordingSampleTiming.retimed(frame, to: CMTime(value: 3, timescale: 1))
        check("a retimed buffer carries the new time",
              moved.map { CMSampleBufferGetPresentationTimeStamp($0) == CMTime(value: 3, timescale: 1) } == true)
        check("and keeps its cadence",
              moved.map { CMSampleBufferGetDuration($0) == CMSampleBufferGetDuration(frame) } == true)
        check("no buffer moves to an invalid time", RecordingSampleTiming.retimed(frame, to: .invalid) == nil)

        var converter: AVAudioConverter?
        let planar = audioSample(at: 0)
        let interleaved = RecordingAudioSample.interleaved(planar, converter: &converter)
        let flags = interleaved.flatMap(CMSampleBufferGetFormatDescription)
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mFormatFlags }
        check("planar sound is interleaved for the encoder",
              flags.map { $0 & kAudioFormatFlagIsNonInterleaved == 0 && $0 & kAudioFormatFlagIsFloat != 0 } == true)
        check("with every frame and its time", interleaved.map {
            CMSampleBufferGetNumSamples($0) == 4_800
                && CMSampleBufferGetPresentationTimeStamp($0) == CMSampleBufferGetPresentationTimeStamp(planar)
        } == true)
        let ready = audioSample(at: 0, interleaved: true)
        check("interleaved Float32 passes as it is", RecordingAudioSample.interleaved(ready, converter: &converter) === ready)
    }

    /// #937 acceptance 1 without capture: 10 s of picture and sound, 2 s off each end, a 6 s file with sound.
    static func recordTrimSave() async {
        let take = scratch.appending(path: "take.mov")
        guard let writer = try? RecordingWriter(
            url: take, width: 160, height: 120, codec: .h264, systemAudio: true, microphone: false), writer.start()
        else { return check("the writer opens an H.264 file with a sound track", false) }
        writer.append(videoSample(at: 0, shade: 0), kind: .video)
        check("nothing is written before the session begins", writer.videoFrameCount == 0)
        writer.beginSession(at: origin)
        for tenth in 0..<100 {
            writer.append(videoSample(at: Double(tenth) / 10, shade: UInt8(tenth * 2)), kind: .video)
            writer.append(audioSample(at: Double(tenth) / 10), kind: .systemAudio)
        }
        check("frames are written", writer.videoFrameCount > 0)
        check("the file is finished", await writer.finish(at: origin + CMTime(value: 10, timescale: 1)))
        let recorded = await seconds(take)
        check("it is as long as the recording, to its stop: \(recorded) s", abs(recorded - 10) < 0.2)
        check("with picture and sound", await hasPictureAndSound(take))

        var trim = RecordingTrim(duration: recorded)
        trim.setStart(2)
        trim.setEnd(8)
        let passes = await RecordingExporter.passthroughWorks(take, .mov)
        check("the clip can be cut without re-encoding", passes)
        let saved = scratch.appending(path: "saved.mov")
        do {
            try await RecordingExporter.export(
                take, trim, .plan(trim, container: .mov, passthroughWorks: passes), saved)
        } catch {
            check("the cut exports: \(error)", false)
        }
        let kept = await seconds(saved)
        check("2 s off each end of 10 s saves 6 s, got \(kept) s", abs(kept - 6) < 0.25)
        check("with picture and sound still", await hasPictureAndSound(saved))
        check("the clip stays until the caller removes it, and nothing is left staged",
              names(in: scratch) == ["saved.mov", "take.mov"])

        let whole = RecordingTrim(duration: recorded)
        let mp4 = scratch.appending(path: "whole.mp4")
        let rewraps = await RecordingExporter.passthroughWorks(take, .mp4)
        try? await RecordingExporter.export(take, whole, .plan(whole, container: .mp4, passthroughWorks: rewraps), mp4)
        let rewrapped = await seconds(mp4)
        check("an uncut MP4 is the whole clip, got \(rewrapped) s", abs(rewrapped - recorded) < 0.25)

        let missing = scratch.appending(path: "missing/out.mov")
        var failed = false
        do { try await RecordingExporter.export(take, trim, .passthrough, missing) } catch { failed = true }
        check("an export that cannot be written fails and leaves nothing behind", failed && !exists(missing)
              && names(in: scratch) == ["saved.mov", "take.mov", "whole.mp4"])

        let moved = scratch.appending(path: "moved.mov")
        try? await RecordingExporter.export(take, whole, .copy, moved)
        check("a clip kept as recorded is moved, not copied", exists(moved) && !exists(take))
    }

    static func emptyAndHEVC() async {
        let empty = scratch.appending(path: "empty.mov")
        let none = try? RecordingWriter(url: empty, width: 160, height: 120, codec: .h264, systemAudio: false, microphone: false)
        let begun = none?.start() == true
        none?.beginSession(at: origin)
        let finished = await none?.finish(at: origin + CMTime(value: 1, timescale: 1))
        check("a recording with no frame is a failure with no file", begun && finished == false && !exists(empty))

        let url = scratch.appending(path: "hevc.mov")
        guard let writer = try? RecordingWriter(
            url: url, width: 160, height: 120, codec: .hevc, systemAudio: false, microphone: true), writer.start()
        else { return check("HEVC opens, or falls back to H.264 where it cannot encode", false) }
        writer.beginSession(at: origin)
        writer.append(videoSample(at: 0, shade: 10), kind: .video)
        writer.append(audioSample(at: 0, interleaved: true), kind: .microphone)
        writer.append(videoSample(at: -1, shade: 10), kind: .video)
        check("a buffer from before the start is dropped", writer.videoFrameCount == 1)
        check("one changing frame still finishes a file", await writer.finish(at: origin + CMTime(value: 2, timescale: 1)))
        let held = await seconds(url)
        check("held to the stop on a still screen, got \(held) s", abs(held - 2) < 0.2)
    }
}
