import Foundation

/// When an account's CLI is asked again: each check starts a process, so rarely while nobody looks.
enum AgentPollPolicy {
    static let shown: TimeInterval = 60
    static let hidden: TimeInterval = 5 * 60
    static let retry: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to the CLI.
    static let settled: TimeInterval = 30 * 60

    /// Each unanswered check in a row doubles the wait up to `settled`, so a dead CLI rarely starts.
    static func interval(after failure: AgentAccountState?, repeated: Int, pageShows: Bool) -> TimeInterval {
        switch failure {
        case nil, .ok?: pageShows ? shown : hidden
        case .unavailable?: min(settled, retry * Double(1 << min(3, max(0, repeated - 1))))
        case .signedOut?, .missing?, .outdated?: settled
        }
    }

    static func isDue(
        lastAttempt: Date?, now: Date, failure: AgentAccountState?, repeated: Int, pageShows: Bool
    ) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval(after: failure, repeated: repeated, pageShows: pageShows)
    }
}
