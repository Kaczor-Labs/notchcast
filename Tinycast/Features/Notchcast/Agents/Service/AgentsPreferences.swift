import Foundation

/// A Claude account as Settings lists it: a name of the user's and Claude Code's config folder.
struct AgentsClaudeAccount: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    /// Empty is Claude Code's own `~/.claude`, signed in as usual.
    var directory: String
}

/// The add-on's own keys in the `<bundle id>.notchcast` suite, so each channel keeps its own.
@MainActor
struct AgentsPreferences {
    static let switchID = "agentsUsage"
    private static let machineKey = "agentsUsage.machineName"
    private static let accountsKey = "agentsUsage.claudeAccounts"
    private static let feedKey = "agentsUsage.feedFolder"

    let defaults: UserDefaults

    var machineName: String? {
        get { defaults.string(forKey: Self.machineKey).flatMap { $0.isEmpty ? nil : $0 } }
        nonmutating set { defaults.set(newValue?.trimmingCharacters(in: .whitespaces), forKey: Self.machineKey) }
    }

    /// Nil until the user edits the list, so `~/.claude` is found by itself.
    var claudeAccounts: [AgentsClaudeAccount]? {
        get {
            defaults.data(forKey: Self.accountsKey)
                .flatMap { try? JSONDecoder().decode([AgentsClaudeAccount].self, from: $0) }
        }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.accountsKey) }
    }

    var feedFolder: String? {
        get { defaults.string(forKey: Self.feedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.feedKey) }
    }

    func folder(default fallback: URL) -> URL {
        feedFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallback
    }

    /// This Mac's accounts: the listed Claude folders, else `~/.claude` when it exists, then Codex.
    func sources(home: URL) -> [AgentsSource] {
        let found = FileManager.default.fileExists(atPath: home.appending(path: ".claude").path)
        let claude = claudeAccounts ?? (found ? [Self.defaultAccount] : [])
        return claude.map { .claude(name: $0.name, directory: $0.directory) } + [.codex]
    }

    static let defaultAccount = AgentsClaudeAccount(name: "Claude", directory: "")
}
