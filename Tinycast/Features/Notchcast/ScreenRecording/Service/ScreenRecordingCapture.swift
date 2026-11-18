// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder session: start order, then stop, drain and finish.

import AVFoundation
import ScreenCaptureKit

/// One recording: the stream, the optional microphone and the writer they feed on one serial queue.
@MainActor
final class ScreenRecordingCapture: RecordingCapture {
    private let session: RecordingSession

    private init(session: RecordingSession) {
        self.session = session
    }

    static func start(_ target: RecordingTarget, _ options: RecordingOptions, _ file: URL,
                      ended: @escaping @MainActor (any Error) -> Void) async throws -> any RecordingCapture {
        ScreenRecordingCapture(session: try await RecordingSession.open(target, options, file, ended: ended))
    }

    func stop() async throws {
        try await session.close()
    }
}

struct RecordingSession: Sendable {
    private let queue: DispatchQueue
    private let writer: RecordingWriter
    private let engine: RecordingCaptureEngine
    private let microphone: RecordingMicrophone?

    @concurrent
    static func open(_ target: RecordingTarget, _ options: RecordingOptions, _ file: URL,
                     ended: @escaping @MainActor (any Error) -> Void) async throws -> RecordingSession {
        let source = try await RecordingCaptureEngine.source(target, systemAudio: options.systemAudio)
        let writer = try RecordingWriter(
            url: file, width: source.configuration.width, height: source.configuration.height,
            codec: options.codec, systemAudio: options.systemAudio, microphone: options.microphone)
        guard writer.start() else { throw RecordingTarget.Failure.captureFailed }
        let queue = DispatchQueue(label: "app.notchcast.recording", qos: .userInitiated)
        let engine = RecordingCaptureEngine(
            queue: queue,
            onSample: { sample, kind in writer.append(sample, kind: kind) },
            onStop: { error in Task { @MainActor in ended(error) } })
        do {
            try await engine.start(filter: source.filter, configuration: source.configuration) { time in
                queue.sync { writer.beginSession(at: time) }
            }
        } catch {
            writer.cancel()
            throw error
        }
        var microphone: RecordingMicrophone?
        if options.microphone {
            let capture = RecordingMicrophone(queue: queue) { writer.append($0, kind: .microphone) }
            guard await capture.start() else {
                await engine.stop()
                writer.cancel()
                throw RecordingTarget.Failure.microphoneUnavailable
            }
            microphone = capture
        }
        return RecordingSession(queue: queue, writer: writer, engine: engine, microphone: microphone)
    }

    /// The stop time is read first, so the file is as long as the recording felt.
    @concurrent
    func close() async throws {
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        await engine.stop()
        await microphone?.stop()
        queue.sync {}
        guard await writer.finish(at: end) else { throw RecordingTarget.Failure.captureFailed }
    }
}
