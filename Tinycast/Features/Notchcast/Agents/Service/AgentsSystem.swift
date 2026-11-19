import Foundation

/// Where one of this Mac's accounts is read from.
enum AgentsSource: Equatable, Sendable {
    case claude(name: String, directory: String)
    case codex

    var name: String {
        switch self {
        case .claude(let name, _): name
        case .codex: "Codex"
        }
    }

    var provider: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}

/// What the module does to the world, so a harness runs it with fake readers, files and clock.
struct AgentsSystem: Sendable {
    var now: @MainActor @Sendable () -> Date
    var computerName: @MainActor @Sendable () -> String
    var home: URL
    var defaultFeedFolder: URL
    var read: @Sendable (AgentsSource) async throws -> AgentAccount
    var readFeed: @Sendable (URL) async -> AgentFeedRead
    var writeLocal: @Sendable (URL, AgentFeed) async -> Void
    var sleep: @Sendable (Duration) async throws -> Void
}

