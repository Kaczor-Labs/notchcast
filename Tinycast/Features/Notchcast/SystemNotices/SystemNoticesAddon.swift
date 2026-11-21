// notchcast-addon-order: 240
import SwiftUI

enum SystemNoticesAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "systemNotices",
            title: String(localized: "System notices", table: "NotchcastSystemNotices"),
            subtitle: String(
                localized: "Tells you on the island when Wi-Fi or a VPN drops or returns, and when the battery runs low.",
                table: "NotchcastSystemNotices"),
            category: .notices
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "systemNotices") {
            AnyView(SystemNoticesSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { SystemNoticesModule(context: context) }
}
