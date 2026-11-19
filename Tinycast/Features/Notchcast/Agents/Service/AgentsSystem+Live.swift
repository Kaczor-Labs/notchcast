import Foundation
import SystemConfiguration
import Synchronization

extension AgentsSystem {
    static func live() -> AgentsSystem {
        let locator = AgentsLocator()
        return AgentsSystem(
            now: { Date() },
            computerName: computerName,
            home: FileManager.default.homeDirectoryForCurrentUser,
            defaultFeedFolder: AppPaths.applicationSupport().appending(path: "Agents", directoryHint: .isDirectory),
            read: { source in
                switch source {
                case .claude(let name, let directory):
                    try await ClaudeUsageReader(
                        name: name, launch: ClaudeLaunch(directory: directory),
                        locate: { await locator.locate("claude") }).read()
                case .codex:
                    try await CodexUsageReader(locate: { await locator.locate("codex") }).read()
                }
            },
            readFeed: { await readFeed($0) },
            writeLocal: { await writeLocal($0, $1) },
            sleep: { try await Task.sleep(for: $0) })
    }

    /// The name in System Settings › General › Sharing, the default for this Mac's column.
    static func computerName() -> String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? String(localized: "This Mac", table: "NotchcastAgents")
    }

    /// A synced folder can stall, so the feed is read off the main actor.
    @concurrent private static func readFeed(_ folder: URL) async -> AgentFeedRead {
        AgentFeedStore(folder: folder).read()
    }

    @concurrent private static func writeLocal(_ folder: URL, _ feed: AgentFeed) async {
        try? AgentFeedStore(folder: folder).writeLocal(feed)
    }
}

/// Finding a CLI asks the login shell, so each is found once and kept while it still runs.
final class AgentsLocator: Sendable {
    private let found = Mutex<[String: URL]>([:])

    func locate(_ command: String) async -> URL? {
        if let url = found.withLock({ $0[command] }), FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        let url = await ExecutableLocator.locate(command)
        found.withLock { $0[command] = url }
        return url
    }
}
