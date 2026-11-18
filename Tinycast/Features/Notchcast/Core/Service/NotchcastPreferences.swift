import Foundation
import Observation

/// The on/off state of every declared switch, stored under the switch id like v1 did.
@MainActor
@Observable
final class NotchcastPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let switches: [String: NotchcastSwitch]
    private var stored: [String: Bool]
    private var launcherHidden: Set<String>
    /// Called on the same turn, so the launcher list never lags its checkbox.
    @ObservationIgnored var onLauncherChange: (() -> Void)?

    nonisolated static let launcherHiddenKey = "launcherHiddenCommands"

    nonisolated static func suiteName(bundleID: String) -> String { bundleID + ".notchcast" }

    init(defaults: UserDefaults, switches: [NotchcastSwitch]) {
        self.defaults = defaults
        self.switches = Dictionary(switches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        stored = self.switches.keys.reduce(into: [:]) { stored, id in
            if let value = defaults.object(forKey: id) as? Bool { stored[id] = value }
        }
        launcherHidden = Set(defaults.stringArray(forKey: Self.launcherHiddenKey) ?? [])
    }

    /// A command's own "Show in launcher", on until the user turns it off.
    func showsInLauncher(_ commandID: String) -> Bool { !launcherHidden.contains(commandID) }

    func setShowsInLauncher(_ commandID: String, _ shown: Bool) {
        guard showsInLauncher(commandID) != shown else { return }
        if shown { launcherHidden.remove(commandID) } else { launcherHidden.insert(commandID) }
        defaults.set(launcherHidden.sorted(), forKey: Self.launcherHiddenKey)
        onLauncherChange?()
    }

    func isDeclared(_ id: String) -> Bool { switches[id] != nil }

    func isOn(_ id: String) -> Bool {
        guard let declared = switches[id] else { return false }
        return stored[id] ?? declared.defaultEnabled
    }

    /// On, with every dependency enabled; a dependency no add-on declares counts as off.
    func isEnabled(_ id: String) -> Bool { isEnabled(id, visiting: []) }

    func set(_ id: String, on: Bool) {
        guard isDeclared(id), isOn(id) != on else { return }
        defaults.set(on, forKey: id)
        stored[id] = on
    }

    private func isEnabled(_ id: String, visiting: Set<String>) -> Bool {
        guard !visiting.contains(id), let declared = switches[id], isOn(id) else { return false }
        let path = visiting.union([id])
        return declared.dependencies.allSatisfy { isEnabled($0, visiting: path) }
    }
}
