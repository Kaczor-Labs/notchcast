import AVFoundation
import Foundation

/// Stock Dictation behind the core's transcription hook, with the user's own model and language.
@MainActor
struct NotchcastDictationBridge: NotchcastTranscribing {
    private nonisolated static let decodeFrames: AVAudioFrameCount = 65_536
    /// Stock Dictation drops a final piece this short rather than transcribe it.
    private nonisolated static let minimumSamples = 1_600

    weak var core: AppCore?

    var isDictating: Bool { core?.dictationCoordinator.isActive ?? false }

    func onUserStart(_ hook: @escaping @MainActor () async -> Void) {
        core?.dictationCoordinator.willStart = hook
    }

    func transcribe(
        _ audioURL: URL, language: String?, isInterrupted: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> String {
        guard let core, core.dictationModels.isInstalled(core.settings.dictationModel) else {
            throw NotchcastTranscribeError.unavailable
        }
        let models = core.dictationModels
        let model = core.settings.dictationModel
        let hint = language ?? core.settings.dictationLanguage
        do {
            return try await Self.transcribe(audioURL) { samples in
                guard !isInterrupted() else { throw NotchcastTranscribeError.busy }
                return try await models.transcribe(samples, model: model, language: hint)
            }
        } catch let failure as DictationWire.Failure {
            switch failure {
            case .notInstalled: throw NotchcastTranscribeError.unavailable
            case .busy: throw NotchcastTranscribeError.busy
            case .unavailable: throw NotchcastTranscribeError.failed(failure.localizedDescription)
            }
        }
    }

    /// Decodes off-main into 16 kHz mono, handing Dictation one request-sized piece at a time.
    @concurrent
    private nonisolated static func transcribe(
        _ url: URL, recognize: @MainActor @Sendable ([Float]) async throws -> String
    ) async throws -> String {
        guard let file = try? AVAudioFile(forReading: url),
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(DictationWire.sampleRate), channels: 1,
                interleaved: false),
            let converter = AVAudioConverter(from: file.processingFormat, to: format),
            let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: decodeFrames),
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: decodeFrames)
        else { throw NotchcastTranscribeError.unreadableAudio }
        let limit = DictationWire.maximumSamples
        var pending: [Float] = []
        var texts: [String] = []
        var decoded = 0
        var ended = false
        while !ended {
            try Task.checkCancellation()
            var readFailed = false
            output.frameLength = 0
            let status = converter.convert(to: output, error: nil) { _, state in
                // Reading past the end throws eofErr, so the end is checked first.
                guard file.framePosition < file.length else { state.pointee = .endOfStream; return nil }
                do { try file.read(into: input) } catch {
                    readFailed = true
                    state.pointee = .endOfStream
                    return nil
                }
                state.pointee = .haveData
                return input
            }
            guard status != .error, !readFailed, let channel = output.floatChannelData?[0] else {
                throw NotchcastTranscribeError.unreadableAudio
            }
            pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            decoded += Int(output.frameLength)
            ended = status == .endOfStream
            while pending.count > limit || (ended && !pending.isEmpty) {
                let cut =
                    pending.count > limit
                    ? DictationAudioChunks.liveCut(in: pending, from: 0, to: limit) : pending.count
                if cut >= minimumSamples {
                    let text = try await recognize(Array(pending[..<cut]))
                    if !text.isEmpty { texts.append(text) }
                }
                pending.removeFirst(cut)
            }
        }
        guard decoded > 0 else { throw NotchcastTranscribeError.unreadableAudio }
        return texts.joined(separator: " ")
    }
}
