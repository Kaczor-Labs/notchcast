// notchcast-new-switch-ids: dayPage
// notchcast-addon-order: 230
// notchcast-readme: Island Content: Day in the Island, a page with the weather, your market quotes and today’s events
import SwiftUI

/// The Day page in the island (#978): weather, market quotes and today's events; off by default.
enum DayAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "dayPage",
            title: String(localized: "Day in the Island", table: "NotchcastDay"),
            subtitle: String(localized: "Weather, your market quotes and today’s events on a page in the island.",
                             table: "NotchcastDay"),
            category: .islandPages),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "dayPage", searchTerms: [
            "city",
            "symbols",
        ]) {
            AnyView(DaySettingsView(context: $0))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DayModule(context: context)
    }
}
