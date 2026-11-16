import Foundation

/// Keep Awake's own preferences, in the add-on suite the core hands it; `keepAwakeMinutes` is v1's key.
struct KeepAwakeSettings: Sendable, Equatable {
    static let durations = [15, 30, 60, 120, 240, 0]
    static let floors = [0, 10, 20, 30, 40, 50]
    static let defaultMinutes = 60
    static let defaultFloor = 20

    var minutes = defaultMinutes
    var batteryFloor = defaultFloor
    var pausesWhenLocked = false
    var restoresSession = true
    var automation = KeepAwakeAutomation.Conditions()

    init() {}

    init(defaults: UserDefaults) {
        minutes = Self.allowed(defaults.object(forKey: Key.minutes) as? Int, Self.durations, Self.defaultMinutes)
        batteryFloor = Self.allowed(defaults.object(forKey: Key.floor) as? Int, Self.floors, Self.defaultFloor)
        pausesWhenLocked = defaults.bool(forKey: Key.pausesWhenLocked)
        restoresSession = defaults.object(forKey: Key.restoresSession) as? Bool ?? true
        automation.externalDisplay = defaults.bool(forKey: Key.autoDisplay)
        automation.power = defaults.bool(forKey: Key.autoPower)
        automation.runningApps = defaults.bool(forKey: Key.autoApps)
        automation.bundleIDs = defaults.stringArray(forKey: Key.autoBundleIDs) ?? []
        automation.requiresAll = defaults.bool(forKey: Key.autoRequiresAll)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(minutes, forKey: Key.minutes)
        defaults.set(batteryFloor, forKey: Key.floor)
        defaults.set(pausesWhenLocked, forKey: Key.pausesWhenLocked)
        defaults.set(restoresSession, forKey: Key.restoresSession)
        defaults.set(automation.externalDisplay, forKey: Key.autoDisplay)
        defaults.set(automation.power, forKey: Key.autoPower)
        defaults.set(automation.runningApps, forKey: Key.autoApps)
        defaults.set(automation.bundleIDs, forKey: Key.autoBundleIDs)
        defaults.set(automation.requiresAll, forKey: Key.autoRequiresAll)
    }

    private static func allowed(_ value: Int?, _ choices: [Int], _ fallback: Int) -> Int {
        value.flatMap { choices.contains($0) ? $0 : nil } ?? fallback
    }

    enum Key {
        static let minutes = "keepAwakeMinutes"
        static let floor = "keepAwakeBatteryFloor"
        static let pausesWhenLocked = "keepAwakePausesWhenLocked"
        static let restoresSession = "keepAwakeRestoresSession"
        static let autoDisplay = "keepAwakeAutoExternalDisplay"
        static let autoPower = "keepAwakeAutoPower"
        static let autoApps = "keepAwakeAutoApps"
        static let autoBundleIDs = "keepAwakeAutoBundleIDs"
        static let autoRequiresAll = "keepAwakeAutoRequiresAll"
        static let session = "keepAwakeSession"
    }
}
