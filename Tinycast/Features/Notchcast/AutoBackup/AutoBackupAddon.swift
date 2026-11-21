// notchcast-addon-order: 130
// notchcast-readme: Mac Tweaks: back up your settings on change and once a day
import SwiftUI

// notchcast-new-switch-ids: autoBackupSettings
enum AutoBackupAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "autoBackupSettings",
            title: String(localized: "Auto-backup settings", table: "NotchcastAutoBackup"),
            subtitle: String(
                localized: "Backs up your settings on change and once a day, into Documents or a folder you choose.",
                table: "NotchcastAutoBackup"),
            category: .macTweaks
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: AutoBackupPreferences.switchID, searchTerms: [
            "backup folder",
            "backups to keep",
        ]) {
            AnyView(AutoBackupSettingsView(context: $0))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        AutoBackupModule(context: context)
    }
}
