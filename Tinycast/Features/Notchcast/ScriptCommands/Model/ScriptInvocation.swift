import Foundation

/// What a run starts: the login shell with `-lc` and the row's script, in the row's folder.
struct ScriptInvocation: Equatable, Sendable {
    /// The Mac facts a run depends on, injected so the harness never reads the real ones.
    struct Environment: Sendable {
        /// `$SHELL`; anything but an absolute path falls back to zsh, the macOS default.
        var shell: String?
        var home: String
        var isExecutableFile: @Sendable (String) -> Bool
        var isDirectory: @Sendable (String) -> Bool
    }

    enum Failure: Error, Equatable {
        case noScript
        case missingFolder(String)
    }

    static let fallbackShell = "/bin/zsh"

    let shell: String
    let arguments: [String]
    let folder: String
    let timeout: Duration

    static func make(for command: ScriptCommand, in environment: Environment) -> Result<Self, Failure> {
        let script = command.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return .failure(.noScript) }
        let typedFolder = command.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = typedFolder.isEmpty ? environment.home : expandingTilde(typedFolder, home: environment.home)
        // A folder that is gone is reported: running somewhere unexpected is worse than not running.
        guard environment.isDirectory(folder) else { return .failure(.missingFolder(typedFolder)) }
        let path = expandingTilde(script, home: environment.home)
        let body = !script.contains("\n") && environment.isExecutableFile(path) ? "exec " + quoted(path) : script
        let shell = environment.shell.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? fallbackShell
        return .success(Self(shell: shell, arguments: ["-lc", body], folder: folder, timeout: command.timeout))
    }

    static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        guard path.hasPrefix("~/") else { return path }
        return home + path.dropFirst()
    }

    /// Single quotes keep a path with spaces or `$` one word the shell never expands.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
