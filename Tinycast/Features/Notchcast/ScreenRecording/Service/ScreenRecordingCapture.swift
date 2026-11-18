// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's capture engine: the stream's configuration and its failures.

import AVFoundation
import ScreenCaptureKit

/// One ScreenCaptureKit stream writing straight to a file through `SCRecordingOutput`.
@MainActor
final class ScreenRecordingCapture: RecordingCapture {
    private let box: StreamBox
    private let ended: @MainActor (any Error) -> Void
    private var listener: Task<Void, Never>?
    private var outcome: Result<Void, any Error>?
    private var waiter: CheckedContinuation<Void, any Error>?
    private var stopping = false

    private init(box: StreamBox, events: AsyncStream<StreamRelay.Event>,
                 ended: @escaping @MainActor (any Error) -> Void) {
        self.box = box
        self.ended = ended
        listener = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .finished: settle(.success(()))
                case .failed(let error):
                    let unexpected = !stopping && outcome == nil
                    settle(.failure(Self.failure(for: error)))
                    if unexpected { self.ended(Self.failure(for: error)) }
                }
            }
        }
    }

    static func start(_ target: RecordingTarget, _ options: RecordingOptions, _ file: URL,
                      ended: @escaping @MainActor (any Error) -> Void) async throws -> any RecordingCapture {
        let (events, continuation) = AsyncStream.makeStream(of: StreamRelay.Event.self)
        do {
            let box = try await open(target, options, file, relay: StreamRelay(events: continuation))
            return ScreenRecordingCapture(box: box, events: events, ended: ended)
        } catch {
            throw failure(for: error)
        }
    }

    /// ScreenCaptureKit's own codes as the few failures a person can act on.
    private static func failure(for error: any Error) -> any Error {
        let streamError = error as NSError
        guard streamError.domain == SCStreamErrorDomain, let code = SCStreamError.Code(rawValue: streamError.code)
        else { return error }
        switch code {
        case .userDeclined: return RecordingTarget.Failure.screenPermission
        case .noWindowList, .noDisplayList, .noCaptureSource: return RecordingTarget.Failure.targetUnavailable
        default: return RecordingTarget.Failure.captureFailed
        }
    }

    /// Returns once the file is finished; a stream that already failed returns at once.
    func stop() async throws {
        stopping = true
        if outcome == nil {
            do { try await Self.stopCapture(box) } catch { settle(.failure(error)) }
        }
        try await withCheckedThrowingContinuation { continuation in
            if let outcome { continuation.resume(with: outcome) } else { waiter = continuation }
        }
        listener?.cancel()
    }

    private func settle(_ result: Result<Void, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        waiter?.resume(with: result)
        waiter = nil
    }

    @concurrent
    private static func stopCapture(_ box: StreamBox) async throws {
        try await box.stream.stopCapture()
    }

    @concurrent
    private static func open(_ target: RecordingTarget, _ options: RecordingOptions, _ file: URL,
                             relay: StreamRelay) async throws -> StreamBox {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        var sourceRect: CGRect?
        var followsWindow = false
        switch target {
        case .area(let rect):
            guard let display = content.displays.first(where: { $0.frame.contains(rect) }),
                let local = RecordingGeometry.sourceRect(rect, onDisplay: display.frame)
            else { throw RecordingTarget.Failure.targetUnavailable }
            filter = SCContentFilter(display: display, excludingWindows: [])
            sourceRect = local
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            followsWindow = true
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        guard let pixels = RecordingGeometry.pixelSize(
            points: sourceRect?.size ?? filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        else { throw RecordingTarget.Failure.targetUnavailable }
        let configuration = SCStreamConfiguration()
        configuration.width = pixels.width
        configuration.height = pixels.height
        if let sourceRect { configuration.sourceRect = sourceRect }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        // A window keeps the size it started at, so a resize scales into it instead of leaving a gap.
        configuration.scalesToFit = followsWindow
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = true
        if options.systemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }
        configuration.captureMicrophone = options.microphone
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = file
        recording.videoCodecType = options.codec == .hevc ? .hevc : .h264
        recording.outputFileType = options.container == .mp4 ? .mp4 : .mov
        let stream = SCStream(filter: filter, configuration: configuration, delegate: relay)
        try stream.addStreamOutput(relay, type: .screen, sampleHandlerQueue: nil)
        if options.systemAudio { try stream.addStreamOutput(relay, type: .audio, sampleHandlerQueue: nil) }
        if options.microphone { try stream.addStreamOutput(relay, type: .microphone, sampleHandlerQueue: nil) }
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: relay))
        try await stream.startCapture()
        return StreamBox(stream: stream)
    }
}

/// Unchecked: built in `open`, then only `stopCapture` touches it, and ScreenCaptureKit serialises that.
private struct StreamBox: @unchecked Sendable {
    let stream: SCStream
}

/// ScreenCaptureKit's callbacks, from its own queues, as events; the frames it hands over are dropped.
private final class StreamRelay: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate, Sendable {
    enum Event: Sendable {
        case finished
        case failed(any Error)
    }

    private let events: AsyncStream<Event>.Continuation

    init(events: AsyncStream<Event>.Continuation) {
        self.events = events
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { events.yield(.failed(error)) }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { events.yield(.finished) }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        events.yield(.failed(error))
    }
}
