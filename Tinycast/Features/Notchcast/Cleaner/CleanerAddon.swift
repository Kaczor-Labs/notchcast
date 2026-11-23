// notchcast-addon-order: 270
// notchcast-readme: Mac Tweaks: a reviewed clean-up of caches and logs to the Trash
// notchcast-new-switch-ids: cleaner
import SwiftUI

enum CleanerAddon: NotchcastAddon {
    static let switchID = "cleaner"

    static let switches = [
        NotchcastSwitch(
            id: switchID,
            title: String(localized: "Cleaner", table: "NotchcastCleaner"),
            subtitle: String(
                localized: "Review app caches, logs and other leftovers, then move the ones you tick to the Trash.",
                table: "NotchcastCleaner"),
            category: .macTweaks),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "clean-up-mac", name: String(localized: "Clean Up Mac", table: "NotchcastCleaner"),
            symbol: "trash", switchID: switchID, keywords: ["cache", "logs", "storage", "space", "trash"],
            run: { $0.module(CleanerModule.self)?.openScreen() },
            diskCleanUpTitle: String(localized: "Clean Up", table: "NotchcastCleaner")),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: switchID) { AnyView(CleanerSettings(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { CleanerModule.live(context) }
}
