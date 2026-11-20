import Foundation

/// How one Claude account is asked: its config folder, and a Claude Code that runs no tool, hook or MCP server.
struct ClaudeLaunch: Equatable, Sendable {
    /// Empty keeps Claude's usual sign-in: naming `~/.claude` would pick another Keychain entry.
    var directory: String

    static let arguments = [
        "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
        "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"
    ]
    /// Opt-outs a person may keep in Claude Code's user settings, which `--setting-sources ""` leaves out.
    static let optOuts = ["DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"]
    static let networkSettings = ["HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"]
    /// Claude Code answers from its saved copy, without asking the account, while it is younger than this.
    static let reuse: TimeInterval = 60

    var isDefault: Bool { directory.isEmpty }

    /// Settings' name for a folder until one is typed: "Claude", or "claude_team" for `.claude_team`.
    static func defaultName(directory: String) -> String {
        directory.isEmpty ? "Claude" : String(URL(filePath: directory).lastPathComponent.trimmingPrefix("."))
    }

    /// Claude Code names its Keychain entry by a hash of this exact text, so `/a/` and `/a` are two sign-ins.
    static func trimmed(_ directory: String) -> String {
        var directory = directory
        while directory.count > 1, directory.hasSuffix("/") { directory.removeLast() }
        return directory
    }

    /// One config folder however it is written: `~` against `home`, empty as `~/.claude`.
    static func path(_ folder: String, home: URL) -> String {
        let folder = folder.isEmpty ? "~/.claude" : folder
        let home = trimmed(home.path(percentEncoded: false))
        let expanded = folder == "~" ? home : folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
        return trimmed(expanded)
    }

    func configurationURL(home: URL) -> URL {
        isDefault ? home.appending(path: ".claude", directoryHint: .isDirectory)
            : URL(fileURLWithPath: directory, isDirectory: true)
    }

    func profileURL(home: URL) -> URL {
        (isDefault ? home : configurationURL(home: home)).appending(path: ".claude.json")
    }

    /// The app may itself run under another agent or account, whose sign-in must not replace this one.
    func environment(_ base: [String: String], settings: Data?) -> [String: String] {
        var environment = base.filter {
            Self.optOuts.contains($0.key) || (!$0.key.hasPrefix("CLAUDE_") && !$0.key.hasPrefix("ANTHROPIC_"))
        }
        environment.removeValue(forKey: "CLAUDECODE")
        if !isDefault { environment["CLAUDE_CONFIG_DIR"] = Self.trimmed(directory) }
        environment["DISABLE_AUTOUPDATER"] = "1"
        guard let settings,
            let json = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any],
            let values = json["env"] as? [String: Any]
        else { return environment }
        // Claude Code lets its settings override the environment, and reads a number or a switch as text.
        for key in Self.optOuts + Self.networkSettings {
            switch values[key] {
            case let text as String: environment[key] = text
            case let number as NSNumber:
                environment[key] =
                    CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
            default: break
            }
        }
        return environment
    }

    /// What `.claude.json` says about the sign-in and the last usage fetch; only compared, never kept.
    struct Profile: Equatable, Sendable {
        var identity: [String?]
        var usageFetched: Date?

        init(_ data: Data?) {
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let account = json["oauthAccount"] as? [String: Any]
            identity = ["accountUuid", "emailAddress", "organizationUuid"].map { account?[$0] as? String }
            let fetched = (json["cachedUsageUtilization"] as? [String: Any])?["fetchedAtMs"] as? NSNumber
            usageFetched = fetched.flatMap { value in
                guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, value.doubleValue > 0
                else { return nil }
                return Date(timeIntervalSince1970: value.doubleValue / 1000)
            }
        }
    }
}
