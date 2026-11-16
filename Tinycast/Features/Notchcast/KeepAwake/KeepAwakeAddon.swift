import SwiftUI

/// F108 Keep Awake and F109 Lid Closed; delete this folder and its registry line to remove both.
enum KeepAwakeAddon: NotchcastAddon {
    static var switches: [NotchcastSwitch] {
        [
            NotchcastSwitch(
                id: "keepAwake",
                title: String(localized: "Keep Awake", table: "NotchcastKeepAwake"),
                subtitle: String(localized: "Prevent idle sleep for the selected duration.", table: "NotchcastKeepAwake"),
                category: .power),
            NotchcastSwitch(
                id: "lidClosedAwake",
                title: String(localized: "Keep Awake with lid closed", table: "NotchcastKeepAwake"),
                subtitle: String(
                    localized: "While Keep Awake is on, closing the lid doesn't sleep the Mac.",
                    table: "NotchcastKeepAwake"),
                category: .power, dependencies: ["keepAwake"])
        ]
    }

    static var commands: [NotchcastCommand] {
        [
            NotchcastCommand(
                slug: "keep-awake", name: String(localized: "Toggle Keep Awake", table: "NotchcastKeepAwake"),
                symbol: "cup.and.saucer", switchID: "keepAwake",
                keywords: ["caffeinate", "sleep", "awake"]
            ) { $0.module(KeepAwakeModule.self)?.toggle() },
            NotchcastCommand(
                slug: "keep-awake-extend", name: String(localized: "Extend Keep Awake", table: "NotchcastKeepAwake"),
                symbol: "clock.arrow.circlepath", switchID: "keepAwake",
                keywords: ["caffeinate", "longer"]
            ) { $0.module(KeepAwakeModule.self)?.extend() }
        ]
    }

    static var settings: [NotchcastSettingsRow] {
        KeepAwakeSettingsRows.all.map { NotchcastSettingsRow(switchID: "keepAwake", view: $0) }
            + [NotchcastSettingsRow(switchID: "lidClosedAwake") { AnyView(KeepAwakeHelperRow(context: $0)) }]
    }

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        KeepAwakeModule(context: context, system: .live())
    }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        KeepAwakeRecovery(context: context, system: .live())
    }
}
