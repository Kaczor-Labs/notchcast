import Foundation

/// Stands in for stock Dictation: no model loads and no helper runs.
@MainActor
final class FakeDictation: NotchcastTranscribing {
    var isDictating = false
    var result: Result<String, any Error> = .success("")
    var holds = false
    var pieces = 1
    /// A model reply that already arrived still comes back after cancellation.
    var finishesDespiteCancel = false
    /// The model store's single guard, held through the async cleanup a cancellation runs.
    private(set) var modelBusy = false
    private(set) var calls: [URL] = []
    private(set) var admittedPieces = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var willStart: @MainActor () async -> Void = {}

    func onUserStart(_ hook: @escaping @MainActor () async -> Void) { willStart = hook }

    func transcribe(_ audioURL: URL, isInterrupted: @escaping @MainActor @Sendable () -> Bool)
        async throws -> String
    {
        calls.append(audioURL)
        modelBusy = true
        defer { modelBusy = false }
        for _ in 0..<pieces {
            guard !isInterrupted() else { throw NotchcastTranscribeError.busy }
            admittedPieces += 1
            if holds { await withCheckedContinuation { held.append($0) } }
            if Task.isCancelled, !finishesDespiteCancel {
                for _ in 0..<5 { await Task.yield() }
                throw CancellationError()
            }
        }
        return try result.get()
    }

    /// Ends every held piece; a held piece ignores cancellation, as a slow helper reply would.
    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    /// The user's own session as stock runs it: start hook, then its transcription meets the guard.
    func userDictates() async -> Bool {
        isDictating = true
        defer { isDictating = false }
        await willStart()
        return !modelBusy
    }
}
