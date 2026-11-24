// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

enum MacTweakGroup: String, CaseIterable, Sendable {
    case finder, dockAndWindows, typing, screenshots, annoyances, appleApps, privacy
}

// notchcast-foreign-strings: the raw values are process names for killall, never shown.
enum MacTweakRestart: String, Codable, CaseIterable, Sendable {
    case finder = "Finder"
    case dock = "Dock"
    case controlCenter = "ControlCenter"
    case windowManager = "WindowManager"
    case systemUIServer = "SystemUIServer"
}

enum MacTweakTarget: Codable, Hashable, Sendable {
    case preference(domain: String, key: String, appOnly: Bool = false)
    case service(label: String)
    case libraryHidden

    // Both global-domain names and either appOnly write the same key of the same layer.
    var canonical: Self {
        guard case .preference(let domain, let key, _) = self else { return self }
        return .preference(domain: domain == ".GlobalPreferences" ? "NSGlobalDomain" : domain, key: key)
    }
}

enum MacTweakChange: Equatable, Sendable {
    case preference(MacTweakTarget, MacTweakValue)
    case service(String)
    case showLibrary
    case dockRemove([String])
    case musicLaunches
    case restriction(String)
    case forced(domain: String, key: String, value: MacTweakValue)

    var localWrite: (target: MacTweakTarget, value: MacTweakValue)? {
        switch self {
        case .preference(let target, let value): (target, value)
        case .service(let label): (.service(label: label), .bool(true))
        case .showLibrary: (.libraryHidden, .bool(false))
        case .dockRemove, .musicLaunches, .restriction, .forced: nil
        }
    }
}

struct MacTweak: Identifiable, Sendable {
    let id: String
    let group: MacTweakGroup
    let changes: [MacTweakChange]
    var restarts: Set<MacTweakRestart> = []
    var since = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
    // A retired tweak stays in the catalogue only so Undo Everything can restore what it wrote.
    var isRetired = false

    func isSupported(on version: OperatingSystemVersion) -> Bool {
        !isRetired && (version.majorVersion, version.minorVersion, version.patchVersion) >=
            (since.majorVersion, since.minorVersion, since.patchVersion)
    }
}

enum MacTweakHeldElsewhere: Codable, Equatable, Sendable {
    case thisMac, everyApp, everyAccount
}

enum MacTweakState: Codable, Equatable, Sendable {
    case applied, notApplied, partial, managed, unsupported
    case heldElsewhere(MacTweakHeldElsewhere)
    case unavailable

    var canChange: Bool {
        switch self {
        case .applied, .notApplied, .partial: true
        case .managed, .unsupported, .heldElsewhere, .unavailable: false
        }
    }
}
