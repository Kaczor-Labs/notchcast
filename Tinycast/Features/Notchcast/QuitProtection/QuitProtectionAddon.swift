// notchcast-addon-order: 30
// notchcast-readme: Keyboard & Mouse: Quit Protection
// notchcast-system-keys: ⌘Q
import SwiftUI

enum QuitProtectionAddon: NotchcastAddon {
    static let switchID = "quitProtection"

    static let switches = [
        NotchcastSwitch(
            id: "quitProtection",
            title: String(localized: "Quit Protection", table: "NotchcastQuitProtection"),
            subtitle: String(
                localized: "Stops an app from quitting on a single slip.", table: "NotchcastQuitProtection"),
            category: .keyboardMouse,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: switchID, searchTerms: [
            "confirm by",
        ]) {
            AnyView(QuitProtectionSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        QuitProtectionModule(context: context, system: .live)
    }
}
