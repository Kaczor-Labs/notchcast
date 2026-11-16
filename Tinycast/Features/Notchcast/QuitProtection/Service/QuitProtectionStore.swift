import Foundation
import Observation

/// The Quit Protection preferences under v1's keys; each write touches only the fields that changed.
@MainActor @Observable
final class QuitProtectionStore {
    nonisolated static let quitEnabledKey = "notchcast.quitProtection.quitEnabled"
    nonisolated static let closeEnabledKey = "notchcast.quitProtection.closeEnabled"
    nonisolated static let modeKey = "notchcast.quitProtection.mode"
    nonisolated static let exceptionsKey = "notchcast.quitProtection.exceptions"
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
            if configuration.closeEnabled != old.closeEnabled {
                defaults.set(configuration.closeEnabled, forKey: Self.closeEnabledKey)
            }
            if configuration.mode != old.mode { defaults.set(configuration.mode.rawValue, forKey: Self.modeKey) }
            if configuration.exceptions != old.exceptions {
                defaults.set(configuration.exceptions.sorted(), forKey: Self.exceptionsKey)
            }
        }
    }

    nonisolated static func configuration(in defaults: UserDefaults) -> QuitProtectionEngine.Configuration {
        .init(
            quitEnabled: defaults.object(forKey: quitEnabledKey) as? Bool ?? true,
            closeEnabled: defaults.bool(forKey: closeEnabledKey),
            mode: defaults.string(forKey: modeKey).flatMap(QuitProtectionEngine.Mode.init) ?? .hold,
            exceptions: Set(defaults.stringArray(forKey: exceptionsKey) ?? []))
    }
}
