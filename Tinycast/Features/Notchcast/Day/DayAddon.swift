import SwiftUI

/// The Day page in the island (#978): weather, chosen market quotes and today's events; off by default.
enum DayAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "dayPage",
            title: String(localized: "Day in the Island", table: "NotchcastDay"),
            subtitle: String(localized: "Weather, your market quotes and today’s events on a page in the island.",
                             table: "NotchcastDay"),
            category: .macTweaks),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "dayPage") { AnyView(DaySettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DayModule(context: context)
    }
}
