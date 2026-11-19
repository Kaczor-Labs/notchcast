import Foundation
import Observation

/// The Quit Protection preferences under v1's keys; each write touches only the fields that changed.
@MainActor @Observable
final class QuitProtectionStore {
    nonisolated static let quitEnabledKey = "notchcast.quitProtection.quitEnabled"
    nonisolated static let modeKey = "notchcast.quitProtection.mode"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = Self.configuration(in: defaults)
    }

    var configuration: QuitProtectionEngine.Configuration {
        didSet {
            let old = oldValue
            if configuration.quitEnabled != old.quitEnabled {
                defaults.set(configuration.quitEnabled, forKey: Self.quitEnabledKey)
            }
            if configuration.mode != old.mode { defaults.set(configuration.mode.rawValue, forKey: Self.modeKey) }
        }
    }

    nonisolated static func configuration(in defaults: UserDefaults) -> QuitProtectionEngine.Configuration {
        .init(
            quitEnabled: defaults.object(forKey: quitEnabledKey) as? Bool ?? true,
            mode: defaults.string(forKey: modeKey).flatMap(QuitProtectionEngine.Mode.init) ?? .hold)
    }
}
