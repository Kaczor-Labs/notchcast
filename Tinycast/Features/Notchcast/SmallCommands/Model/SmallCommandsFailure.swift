import Foundation

nonisolated enum SmallCommandsFailure: LocalizedError, Equatable, Sendable {
    case noLink
    case shortenFailed
    case copyFailed
    case browserNeedsAutomation
    case finderNeedsAutomation
    case appTimedOut
    case controlCenterNotRunning
    case controlCenterMenuOpen
    case controlCenterUnresponsive
    case needsAccessibility
    case noAirPods
    case noiseControlUnchanged
    case airDropCancelled
    case nothingSelected
    case airDropUnavailable

    var errorDescription: String? {
        switch self {
        case .noLink:
            String(localized: "No link in the clipboard or the browser.", table: "NotchcastSmallCommands")
        case .shortenFailed:
            String(localized: "TinyURL did not return a short link.", table: "NotchcastSmallCommands")
        case .copyFailed:
            String(localized: "Could not copy to the clipboard.", table: "NotchcastSmallCommands")
        case .browserNeedsAutomation:
            String(localized: "Allow Automation access to read the browser's address.", table: "NotchcastSmallCommands")
        case .finderNeedsAutomation:
            String(localized: "Allow Automation access to read the Finder selection.", table: "NotchcastSmallCommands")
        case .appTimedOut:
            String(localized: "The app did not respond in time.", table: "NotchcastSmallCommands")
        case .controlCenterNotRunning:
            String(localized: "Control Center is not running.", table: "NotchcastSmallCommands")
        case .controlCenterMenuOpen:
            String(localized: "Close the open Control Center menu and try again.", table: "NotchcastSmallCommands")
        case .controlCenterUnresponsive:
            String(localized: "Control Center did not respond.", table: "NotchcastSmallCommands")
        case .needsAccessibility:
            String(localized: "Allow Accessibility access to switch noise control.", table: "NotchcastSmallCommands")
        case .noAirPods:
            String(localized: "No AirPods with noise control found.", table: "NotchcastSmallCommands")
        case .noiseControlUnchanged:
            String(localized: "Noise control did not change.", table: "NotchcastSmallCommands")
        case .airDropCancelled:
            String(localized: "AirDrop was cancelled.", table: "NotchcastSmallCommands")
        case .nothingSelected:
            String(localized: "Select files in Finder first.", table: "NotchcastSmallCommands")
        case .airDropUnavailable:
            String(localized: "AirDrop is unavailable.", table: "NotchcastSmallCommands")
        }
    }
}
