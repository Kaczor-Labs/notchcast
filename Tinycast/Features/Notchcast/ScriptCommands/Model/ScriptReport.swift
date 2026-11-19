import Foundation

/// The island's words for a finished run: the name, the outcome and the script's last line.
struct ScriptReport: Equatable, Sendable {
    static let lastLineLimit = 200

    var text: String
    var isFailure: Bool

    init(name: String, result: ScriptRun.Result, timeoutMinutes: Int) {
        let line = Self.lastLine(of: result.output)
        switch result.outcome {
        case .exited(0):
            text = String(localized: "\(name) finished", table: "NotchcastScriptCommands")
            isFailure = false
            return
        case .exited(let status):
            text = if let line {
                String(localized: "\(name) failed (exit \(Int(status))): \(line)", table: "NotchcastScriptCommands")
            } else {
                String(localized: "\(name) failed (exit \(Int(status)))", table: "NotchcastScriptCommands")
            }
        case .timedOut:
            text = String(
                localized: "\(name) stopped after \(timeoutMinutes) min", table: "NotchcastScriptCommands")
        case .couldNotStart(let reason):
            text = String(localized: "\(name) could not start: \(reason)", table: "NotchcastScriptCommands")
        }
        isFailure = true
    }

    init(name: String, failure: ScriptInvocation.Failure) {
        text = switch failure {
        case .noScript:
            String(localized: "\(name) has no script", table: "NotchcastScriptCommands")
        case .missingFolder(let folder):
            String(localized: "\(name) could not start: no folder at \(folder)", table: "NotchcastScriptCommands")
        }
        isFailure = true
    }

    /// The last line with any text; a bare carriage return ends a line too, as progress bars use it.
    static func lastLine(of output: String) -> String? {
        let line = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
        guard let line else { return nil }
        return line.count > lastLineLimit ? String(line.prefix(lastLineLimit - 1)) + "…" : line
    }
}
