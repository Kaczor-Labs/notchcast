// notchcast-linux-ok
// notchcast-sources: Tinycast/Migrations/ICloudSyncOffMigration.swift
// notchcast-sources: Tinycast/Features/Settings/AppSettingsKey.swift
import Foundation

@main
struct ICloudSyncOffMigrationTest {
    static func main() {
        let suite = "notchcast.icloud-sync-off-migration.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = AppSettingsKey.iCloudSyncEnabled.rawValue
        defaults.set(true, forKey: key)
        defaults.set(true, forKey: AppSettingsKey.clipboardEnabled.rawValue)
        ICloudSyncOffMigration.run(defaults: defaults)
        precondition(defaults.object(forKey: key) == nil, "A stored iCloud Sync switch is cleared")
        precondition(defaults.bool(forKey: AppSettingsKey.clipboardEnabled.rawValue), "Other settings stay")
        ICloudSyncOffMigration.run(defaults: defaults)
        precondition(defaults.object(forKey: key) == nil, "A second run changes nothing")
        print("iCloud Sync off migration: a stored switch is cleared, other settings stay")
    }
}
