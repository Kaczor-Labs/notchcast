import Foundation

/// What became of one cleanup: the text to paste, or why the raw transcript goes instead.
enum DictationCleanupOutcome: Equatable, Sendable {
    enum Failure: Equatable, Sendable { case error, timeout, empty }

    case cleaned(String)
    /// Cleanup is off, Return skipped it, or no model is available: raw text, no notice.
    case skipped
    /// The reader asked for cleanup and did not get it, so the paste says so.
    case failed(Failure)
}

enum DictationCleanupRunner {
    static let timeout = Duration.seconds(10)

    /// Races `generate` against `deadline`; the first to finish decides, the other is cancelled.
    static func run(
        _ transcript: String,
        generate: (@Sendable () async throws -> String)?,
        deadline: @escaping @Sendable () async throws -> Void
    ) async -> DictationCleanupOutcome {
        guard let generate, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .skipped }
        return await withTaskGroup(of: DictationCleanupOutcome?.self) { group in
            group.addTask {
                do {
                    let text = try await generate().trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? .failed(.empty) : .cleaned(text)
                } catch {
                    return .failed(.error)
                }
            }
            group.addTask {
                // A cancelled deadline means the model answered first, so it decides nothing.
                do { try await deadline() } catch { return nil }
                return .failed(.timeout)
            }
            for await outcome in group {
                guard let outcome else { continue }
                // Escape cancels the session; its failed model call must not report a skip.
                let cancelled = Task.isCancelled
                group.cancelAll()
                return cancelled ? .skipped : outcome
            }
            return .failed(.error)
        }
    }
}
