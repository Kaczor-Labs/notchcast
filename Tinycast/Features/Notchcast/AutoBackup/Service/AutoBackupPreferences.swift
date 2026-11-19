import Foundation

/// The add-on's own keys in the `<bundle id>.notchcast` suite, so each channel keeps its own.
@MainActor
struct AutoBackupPreferences {
    static let switchID = "autoBackupSettings"
    private static let folderKey = "autoBackupSettings.folder"
    private static let keepKey = "autoBackupSettings.keep"
    private static let scheduleKey = "autoBackupSettings.schedule"

    let defaults: UserDefaults

    var chosenFolder: String? {
        get { defaults.string(forKey: Self.folderKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.folderKey) }
    }

    var keep: Int {
        get { defaults.object(forKey: Self.keepKey) as? Int ?? AutoBackupSchedule.defaultKeep }
        nonmutating set { defaults.set(newValue, forKey: Self.keepKey) }
    }

    var schedule: AutoBackupSchedule {
        get {
            defaults.data(forKey: Self.scheduleKey)
                .flatMap { try? JSONDecoder().decode(AutoBackupSchedule.self, from: $0) } ?? AutoBackupSchedule()
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.scheduleKey) }
    }

    /// Read and saved in one step, so a stopped run's late write never overwrites a newer state.
    func update<T>(_ change: (inout AutoBackupSchedule) -> T) -> T {
        var current = schedule
        let result = change(&current)
        schedule = current
        return result
    }

    /// Debug builds write into a subfolder named by their bundle id, so channels never mix.
    var folder: URL {
        #if DEBUG
            let channel = Bundle.main.bundleIdentifier
        #else
            let channel: String? = nil
        #endif
        return AutoBackupSchedule.folder(chosen: chosenFolder, documents: .documentsDirectory, channel: channel)
    }
}
