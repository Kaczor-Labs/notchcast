// notchcast-addon-order: 250
import SwiftUI

enum AccessoriesAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "accessoryNotices",
            title: String(localized: "Accessories", table: "NotchcastAccessories"),
            subtitle: String(
                localized: "Shows on the island when a Bluetooth accessory connects or its battery runs low, and lists connected accessories with their battery levels.",
                table: "NotchcastAccessories"),
            category: .notices
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "accessoryNotices") {
            AnyView(AccessoriesSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { AccessoriesModule(context: context) }
}
