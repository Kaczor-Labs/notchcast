// notchcast-addon-order: 100
// notchcast-readme: Mac Tweaks: turn off iPhone auto backups
import SwiftUI

enum IPhoneBackupAddon: NotchcastAddon {
    static let switchID = "iPhoneBackupTweaks"

    static let switches = [
        NotchcastSwitch(
            id: "iPhoneBackupTweaks",
            title: String(localized: "Turn off iPhone auto backups", table: "NotchcastIPhoneBackup"),
            subtitle: String(
                localized: "Asks first, and switching back restores your previous setting.",
                table: "NotchcastIPhoneBackup"),
            category: .macTweaks
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: switchID) {
            AnyView(IPhoneBackupSettingsView(store: IPhoneBackupStore(context: $0, system: .live)))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        IPhoneBackupModule(context: context, system: .live)
    }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        IPhoneBackupRecovery(context: context, system: .live)
    }
}
