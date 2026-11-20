import Foundation

/// Why a Taildrop run stopped; each case is one island notice.
nonisolated enum TaildropFailure: Error, Equatable, Sendable {
    case notInstalled
    case notRunning
    case signedOut
    case noDevices
    case deviceGone
    case deviceOffline(String)
    case nothingSelected
    case finderAutomation
    case zipFailed(String)
    /// The CLI's own last error line, empty when it printed none.
    case refused(String)

    private struct Status: Decodable {
        let backendState: String

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
        }
    }

    /// Why the device listing failed, read from `tailscale status --json` rather than from prose.
    static func listing(status: String, errors: String) -> TaildropFailure {
        guard let state = try? JSONDecoder().decode(Status.self, from: Data(status.utf8)).backendState else {
            return .notRunning
        }
        switch state {
        case "NeedsLogin", "NeedsMachineAuth": return .signedOut
        case "Running": return .refused(lastLine(errors))
        default: return .notRunning
        }
    }

    static func lastLine(_ errors: String) -> String {
        let line = errors.split(whereSeparator: \.isNewline).last { !$0.allSatisfy(\.isWhitespace) } ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(120))
    }

    var message: String {
        switch self {
        case .notInstalled: String(localized: "Tailscale is not installed.", table: "NotchcastTaildrop")
        case .notRunning: String(localized: "Tailscale is not running.", table: "NotchcastTaildrop")
        case .signedOut: String(localized: "Tailscale is signed out.", table: "NotchcastTaildrop")
        case .noDevices: String(localized: "No device can receive files.", table: "NotchcastTaildrop")
        case .deviceGone: String(localized: "That device no longer receives files.", table: "NotchcastTaildrop")
        case .deviceOffline(let name): String(localized: "\(name) is offline.", table: "NotchcastTaildrop")
        case .nothingSelected: String(localized: "Select files in Finder first.", table: "NotchcastTaildrop")
        case .finderAutomation:
            String(localized: "Allow Automation access to read the Finder selection.", table: "NotchcastTaildrop")
        case .zipFailed(let name): String(localized: "Could not zip \(name).", table: "NotchcastTaildrop")
        case .refused(""): Self.unknown
        case .refused(let reason): String(localized: "Taildrop failed: \(reason)", table: "NotchcastTaildrop")
        }
    }

    static var unknown: String { String(localized: "Taildrop failed.", table: "NotchcastTaildrop") }
}
