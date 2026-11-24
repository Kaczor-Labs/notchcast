import Foundation
import Synchronization

/// The Notchcast sidebar section's tabs, in order; a later add-on adds its tab here.
enum NotchcastPane: CaseIterable, Sendable {
    case island, islandContent, agents, keyboardMouse, dictation, displaySound, capture, clipboardFiles, downloads,
         launcher, macTweaks

    /// Installed by NotchcastCore from the registered switches before Settings can open.
    private static let registered = Mutex<Set<NotchcastCategory>>([])

    /// Island and Dictation always; an add-on tab only while a registered switch sits in one of its categories.
    static var shown: [NotchcastPane] { shown(registered: registered.withLock { $0 }) }

    static func shown(registered: Set<NotchcastCategory>) -> [NotchcastPane] {
        allCases.filter { [.island, .dictation].contains($0) || !registered.isDisjoint(with: $0.categories) }
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
        case .island: []
        case .islandContent: [.islandPages, .notices]
        case .agents: [.agents]
        case .keyboardMouse: [.keyboardMouse]
        case .dictation: []
        case .displaySound: [.display, .sound]
        case .capture: [.capture]
        case .clipboardFiles: [.clipboard, .finder, .files]
        case .downloads: [.downloads]
        case .launcher: [.launcher]
        case .macTweaks: [.macTweaks]
        }
    }

    /// `tinycast://settings/<slug>`; spelled out, so renaming a case never breaks a saved link.
    var slug: String {
        switch self {
        case .island: "notchcast-island"
        case .islandContent: "notchcast-island-content"
        case .agents: "notchcast-agents"
        case .keyboardMouse: "notchcast-keyboard-mouse"
        case .dictation: "notchcast-dictation"
        case .displaySound: "notchcast-display-sound"
        case .capture: "notchcast-capture"
        case .clipboardFiles: "notchcast-clipboard-files"
        case .downloads: "notchcast-downloads"
        case .launcher: "notchcast-launcher"
        case .macTweaks: "notchcast-mac-tweaks"
        }
    }

    var title: String {
        switch self {
        case .island: String(localized: "Island", table: "Notchcast")
        case .islandContent: String(localized: "Island Content", table: "Notchcast")
        case .agents: String(localized: "Agents", table: "Notchcast")
        case .keyboardMouse: String(localized: "Keyboard & Mouse", table: "Notchcast")
        case .dictation: String(localized: "Dictation")
        case .displaySound: String(localized: "Display & Sound", table: "Notchcast")
        case .capture: String(localized: "Capture", table: "Notchcast")
        case .clipboardFiles: String(localized: "Clipboard & Files", table: "Notchcast")
        case .downloads: String(localized: "Downloads", table: "Notchcast")
        case .launcher: String(localized: "Launcher Extras", table: "Notchcast")
        case .macTweaks: String(localized: "Mac Tweaks", table: "Notchcast")
        }
    }

    var systemImage: String {
        switch self {
        case .island: "capsule.fill"
        case .islandContent: "rectangle.stack.fill"
        case .agents: "gauge.with.needle"
        case .keyboardMouse: "keyboard"
        case .dictation: "waveform"
        case .displaySound: "speaker.wave.2"
        case .capture: "camera.viewfinder"
        case .clipboardFiles: "doc.on.clipboard.fill"
        case .downloads: "arrow.down.circle"
        case .launcher: "plus.magnifyingglass"
        case .macTweaks: "wrench.and.screwdriver"
        }
    }
}
