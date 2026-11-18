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
                    settle(.failure(error))
                    if unexpected { self.ended(error) }
                }
            }
        }
    }

    static func start(_ target: RecordingTarget, _ options: RecordingOptions, _ file: URL,
                      ended: @escaping @MainActor (any Error) -> Void) async throws -> any RecordingCapture {
        let (events, continuation) = AsyncStream.makeStream(of: StreamRelay.Event.self)
        let box = try await open(target, options, file, relay: StreamRelay(events: continuation))
        return ScreenRecordingCapture(box: box, events: events, ended: ended)
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
        configuration.showsCursor = true
        configuration.capturesAudio = options.systemAudio
        configuration.excludesCurrentProcessAudio = true
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
