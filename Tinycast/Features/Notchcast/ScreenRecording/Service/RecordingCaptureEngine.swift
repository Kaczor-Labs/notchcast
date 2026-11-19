// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's capture engine: the stream, its filter and host-clock samples.

import AVFoundation
import ScreenCaptureKit

/// Unchecked: `lock` guards the lifecycle and the stream; samples arrive on the session queue.
final class RecordingCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue: DispatchQueue
    private let onSample: @Sendable (CMSampleBuffer, RecordingWriter.Kind) -> Void
    private let onStop: @Sendable (any Error) -> Void
    private let lock = NSLock()
    private var lifecycle = RecordingCaptureLifecycle()
    private var stream: SCStream?

    init(queue: DispatchQueue, onSample: @escaping @Sendable (CMSampleBuffer, RecordingWriter.Kind) -> Void,
         onStop: @escaping @Sendable (any Error) -> Void) {
        self.queue = queue
        self.onSample = onSample
        self.onStop = onStop
    }

    /// What to record and at what size, resolved once: a window keeps the size it starts with.
    static func source(
        _ target: RecordingTarget, systemAudio: Bool
    ) async throws -> (filter: SCContentFilter, configuration: SCStreamConfiguration) {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw failure(for: error)
        }
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter
        var area: CGRect?
        switch target {
        case .area(let rect):
            guard let display = content.displays.first(where: { $0.frame.contains(rect) }),
                let local = RecordingGeometry.sourceRect(rect, onDisplay: display.frame)
            else { throw RecordingTarget.Failure.targetUnavailable }
            filter = SCContentFilter(display: display, excludingWindows: [])
            area = local
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            // Scaled into the starting size, a later resize follows the recording, not an empty frame.
            configuration.scalesToFit = true
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        guard let pixels = RecordingEncoding.pixelSize(
            points: area?.size ?? filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        else { throw RecordingTarget.Failure.targetUnavailable }
        configuration.width = pixels.width
        configuration.height = pixels.height
        if let area { configuration.sourceRect = area }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(RecordingEncoding.frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.showsCursor = true
        configuration.shouldBeOpaque = true
        // Shadows belong to the desktop, not to the thing recorded.
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true
        if systemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }
        return (filter, configuration)
    }

    /// `willStart` gets the host time just before capture, which becomes the file's zero.
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration,
               willStart: (CMTime) -> Void) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if configuration.capturesAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            let begun = lock.withLock { () -> Bool in
                guard self.stream == nil, lifecycle.beginStart() else { return false }
                self.stream = stream
                return true
            }
            guard begun else { throw RecordingTarget.Failure.captureFailed }
            willStart(CMClockGetTime(CMClockGetHostTimeClock()))
            try await stream.startCapture()
        } catch {
            await stop()
            throw Self.failure(for: error)
        }
        guard lock.withLock({ lifecycle.didStart() }) else {
            await stop()
            throw RecordingTarget.Failure.captureFailed
        }
    }

    /// Waits for the stream and drains the queue, so the writer finishes with no buffer on its way.
    func stop() async {
        let stream = lock.withLock { () -> SCStream? in
            lifecycle.stop()
            defer { self.stream = nil }
            return self.stream
        }
        if let stream { try? await stream.stopCapture() }
        queue.sync {}
    }

    private static func failure(for error: any Error) -> any Error {
        if error is RecordingTarget.Failure { return error }
        let failure = error as NSError
        guard failure.domain == SCStreamErrorDomain, let code = SCStreamError.Code(rawValue: failure.code) else {
            return RecordingTarget.Failure.captureFailed
        }
        switch code {
        case .userDeclined: return RecordingTarget.Failure.screenPermission
        case .noWindowList, .noDisplayList, .noCaptureSource: return RecordingTarget.Failure.targetUnavailable
        default: return RecordingTarget.Failure.captureFailed
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard lock.withLock({ lifecycle.acceptsSamples && self.stream === stream }),
            CMSampleBufferIsValid(sampleBuffer), let clock = stream.synchronizationClock
        else { return }
        let kind: RecordingWriter.Kind
        switch type {
        case .screen:
            guard Self.carriesPixels(sampleBuffer) else { return }
            kind = .video
        case .audio: kind = .systemAudio
        default: return
        }
        guard let synchronized = RecordingSampleTiming.converted(
            sampleBuffer, from: clock, to: CMClockGetHostTimeClock())
        else { return }
        onSample(synchronized, kind)
    }

    /// An idle or blank frame would fault the writer; a still screen writes nothing, at no cost.
    private static func carriesPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete || status == .started
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let unexpected = lock.withLock { () -> Bool in
            guard lifecycle.acceptsSamples, self.stream === stream else { return false }
            lifecycle.stop()
            self.stream = nil
            return true
        }
        if unexpected { onStop(error) }
    }
}
