import Foundation
import Synchronization

/// The Notchcast sidebar section's tabs, in order; a later add-on adds its tab here.
enum NotchcastPane: CaseIterable, Sendable {
    case island, keyboardMouse, displaySound, capture, launcher, downloads, macTweaks

    /// Installed by NotchcastCore from the registered switches before Settings can open.
    private static let registered = Mutex<Set<NotchcastCategory>>([])

    /// Island always; an add-on tab only while a registered switch sits in one of its categories.
    static var shown: [NotchcastPane] { shown(registered: registered.withLock { $0 }) }

    static func shown(registered: Set<NotchcastCategory>) -> [NotchcastPane] {
        allCases.filter { $0 == .island || !registered.isDisjoint(with: $0.categories) }
    }

    /// The one tab a category sits in; the core harness pins that each sits in exactly one.
    static func holding(_ category: NotchcastCategory) -> NotchcastPane {
        allCases.first { $0.categories.contains(category) } ?? .island
    }

    static func install(_ categories: Set<NotchcastCategory>) {
        registered.withLock { $0 = categories }
    }

    var categories: [NotchcastCategory] {
        switch self {
        case .island: [.notices]
        case .keyboardMouse: [.keyboardMouse]
        case .displaySound: [.displaySound, .music]
        case .capture: [.capture]
        case .launcher: [.launcher]
        case .downloads: [.filesDownloads]
        case .macTweaks: [.macTweaks]
        }
    }

    /// `tinycast://settings/<slug>`; spelled out, so renaming a case never breaks a saved link.
    var slug: String {
        switch self {
        case .island: "notchcast-island"
        case .keyboardMouse: "notchcast-keyboard-mouse"
        case .displaySound: "notchcast-display-sound"
        case .capture: "notchcast-capture"
        case .launcher: "notchcast-launcher"
        case .downloads: "notchcast-downloads"
        case .macTweaks: "notchcast-mac-tweaks"
        }
    }

    var title: String {
        switch self {
        case .island: String(localized: "Island", table: "Notchcast")
        case .keyboardMouse: String(localized: "Keyboard & Mouse", table: "Notchcast")
        case .displaySound: String(localized: "Display & Sound", table: "Notchcast")
        case .capture: String(localized: "Capture", table: "Notchcast")
        case .launcher: String(localized: "Launcher Extras", table: "Notchcast")
        case .downloads: String(localized: "Downloads", table: "Notchcast")
        case .macTweaks: String(localized: "Mac Tweaks", table: "Notchcast")
        }
    }

    var systemImage: String {
        switch self {
        case .island: "capsule.fill"
        case .keyboardMouse: "keyboard"
        case .displaySound: "speaker.wave.2"
        case .capture: "camera.viewfinder"
        case .launcher: "plus.magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .macTweaks: "wrench.and.screwdriver"
        }
    }
}
