import Foundation

enum TaildropFailure: LocalizedError, Equatable, Sendable {
    case nothingSelected
    case notInstalled
    case notRunning
    case notConnected
    case busy
    case finderNeedsAutomation
    case finderTimedOut
    case unreadable(String)
    case zipFailed(String)
    /// What `tailscale` gave as its reason, shown as it is.
    case refused(String)

    static let reasonLimit = 120

    /// A failed `tailscale` run ends with its error; lines before it are warnings or progress.
    init(output: String) {
        let text = output.lowercased()
        if text.contains("not connected to the tailnet") || text.contains("logged out") {
            self = .notConnected
        } else if text.contains("failed to connect to local tailscale") || text.contains("not running") {
            self = .notRunning
        } else {
            let last = output.split(whereSeparator: \.isNewline).last ?? ""
            self = .refused(String(last.trimmingCharacters(in: .whitespaces).prefix(Self.reasonLimit)))
        }
    }

    var errorDescription: String? {
        switch self {
        case .nothingSelected:
            String(localized: "Select files or folders in Finder first.", table: "NotchcastTaildrop")
        case .notInstalled:
            String(localized: "Tailscale is not installed.", table: "NotchcastTaildrop")
        case .notRunning:
            String(localized: "Tailscale is not running.", table: "NotchcastTaildrop")
        case .notConnected:
            String(localized: "Tailscale is signed out or disconnected.", table: "NotchcastTaildrop")
        case .busy:
            String(localized: "A Taildrop is already running.", table: "NotchcastTaildrop")
        case .finderNeedsAutomation:
            String(localized: "Allow Automation access to read the Finder selection.", table: "NotchcastTaildrop")
        case .finderTimedOut:
            String(localized: "Finder did not respond in time.", table: "NotchcastTaildrop")
        case .unreadable(let name):
            String(localized: "Could not read \(name).", table: "NotchcastTaildrop")
        case .zipFailed(let name):
            String(localized: "Could not zip \(name).", table: "NotchcastTaildrop")
        case .refused(let reason):
            reason.isEmpty ? String(localized: "Taildrop failed.", table: "NotchcastTaildrop") : reason
        }
    }
}
