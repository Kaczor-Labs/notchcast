import SwiftUI

enum AutoBackupAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "autoBackupSettings",
            title: String(localized: "Auto-backup settings", table: "NotchcastAutoBackup"),
            subtitle: String(
                localized: "Saves a settings backup to a folder on change and once a day, such as Documents in iCloud Drive.",
                table: "NotchcastAutoBackup"),
            category: .macTweaks
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: AutoBackupPreferences.switchID) {
            AnyView(AutoBackupSettingsView(context: $0))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        AutoBackupModule(context: context)
    }
}
