import Foundation

enum NotchcastTranscribeError: Error, Equatable, Sendable {
    /// No dictation model is installed, or stock Dictation cannot run.
    case unavailable
    /// The user's own dictation, or another add-on's transcription, holds Dictation.
    case busy
    case unreadableAudio
    case failed(String)
}

/// Stock Dictation as the core sees it; `NotchcastCore` injects the real one.
@MainActor
protocol NotchcastTranscribing: Sendable {
    /// The user is recording, or a dictation of theirs is still being transcribed.
    var isDictating: Bool { get }
    /// Installs what stock Dictation awaits when the user starts, before its microphone opens.
    func onUserStart(_ hook: @escaping @MainActor () async -> Void)
    /// Asks `isInterrupted` before each piece of audio enters the model, and stops when it says so.
    func transcribe(_ audioURL: URL, isInterrupted: @escaping @MainActor @Sendable () -> Bool)
        async throws -> String
}

/// One transcription at a time across add-ons, and never alongside the user's own dictation.
@MainActor
final class NotchcastTranscriptionRunner {
    private let dictation: any NotchcastTranscribing
    private var running: Task<String, any Error>?
    private var userStarts = 0

    init(dictation: any NotchcastTranscribing) {
        self.dictation = dictation
        dictation.onUserStart { [weak self] in await self?.yieldToUser() }
    }

    /// The user's dictation waits until ours has let go of the model, so it is never refused busy.
    private func yieldToUser() async {
        userStarts += 1
        guard let running else { return }
        running.cancel()
        _ = await running.result
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        try Task.checkCancellation()
        guard running == nil, !dictation.isDictating else { throw NotchcastTranscribeError.busy }
        let start = userStarts
        let dictation = dictation
        let isInterrupted: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.userStarts != start || dictation.isDictating
        }
        let task = Task { try await dictation.transcribe(audioURL, isInterrupted: isInterrupted) }
        running = task
        defer { running = nil }
        let result = await withTaskCancellationHandler { await task.result } onCancel: { task.cancel() }
        try Task.checkCancellation()
        // A start counts even after that dictation ended: ours overlapped it, so its text is void.
        guard !isInterrupted() else { throw NotchcastTranscribeError.busy }
        do { return try result.get() } catch {
            throw error as? NotchcastTranscribeError ?? .failed(error.localizedDescription)
        }
    }
}
