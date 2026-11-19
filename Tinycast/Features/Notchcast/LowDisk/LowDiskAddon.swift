import SwiftUI

enum LowDiskAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "lowDiskWarning",
            title: String(localized: "Low disk warning", table: "NotchcastLowDisk"),
            subtitle: String(localized: "Warns on the island when the startup disk is nearly full.",
                             table: "NotchcastLowDisk"),
            category: .power
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "check-disk-space", name: String(localized: "Check Disk Space", table: "NotchcastLowDisk"),
            symbol: LowDiskModule.symbol, switchID: "lowDiskWarning", keywords: ["free", "storage", "space"],
            run: { $0.module(LowDiskModule.self)?.showFreeSpace() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "lowDiskWarning") { AnyView(LowDiskSettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { LowDiskModule(context: context) }
}
