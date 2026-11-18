import Foundation

/// #910: our builds carry no iCloud entitlement, so a switch turned on there is cleared, not kept.
enum ICloudSyncOffMigration {
    static func run(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppSettingsKey.iCloudSyncEnabled.rawValue)
    }
}
