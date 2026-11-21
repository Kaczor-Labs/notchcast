import Foundation

/// A Notchcast Settings section; an add-on picks one, `NotchcastPane` places it, empty ones hide.
enum NotchcastCategory: String, CaseIterable, Sendable {
    case capture
    case display
    case sound
    case keyboardMouse
    case launcher
    case clipboard
    case finder
    case files
    case downloads
    case islandPages
    case notices
    case betweenMacs
    case macTweaks

    var title: String {
        switch self {
        case .capture: String(localized: "Capture", table: "Notchcast")
        case .display: String(localized: "Display")
        case .sound: String(localized: "Sound", table: "Notchcast")
        case .keyboardMouse: String(localized: "Keyboard & Mouse", table: "Notchcast")
        case .launcher: String(localized: "Launcher Extras", table: "Notchcast")
        case .clipboard: String(localized: "Clipboard")
        case .finder: String(localized: "Finder", table: "Notchcast")
        case .files: String(localized: "Files")
        case .downloads: String(localized: "Downloads", table: "Notchcast")
        case .islandPages: String(localized: "Pages", table: "Notchcast")
        case .notices: String(localized: "Notices", table: "Notchcast")
        case .betweenMacs: String(localized: "Between Macs", table: "Notchcast")
        case .macTweaks: String(localized: "Mac Tweaks", table: "Notchcast")
        }
    }
}
