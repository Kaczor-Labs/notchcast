import SwiftUI

enum SystemToolsAddon: NotchcastAddon {
    static let switchID = "systemTools"

    static let switches = [
        NotchcastSwitch(
            id: "systemTools",
            title: String(localized: "System tools", table: "NotchcastSystemTools"),
            subtitle: String(
                localized: "Kill a process, test your network, and Touch ID for sudo.", table: "NotchcastSystemTools"),
            category: .macTweaks
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "kill-process", name: String(localized: "Kill Process", table: "NotchcastSystemTools"),
            symbol: KillProcessSession.symbol, switchID: "systemTools",
            keywords: ["quit", "force quit", "process", "cpu", "memory"],
            run: { $0.module(SystemToolsModule.self)?.killProcess() }),
        NotchcastCommand(
            slug: "network-quality", name: String(localized: "Test Network Quality", table: "NotchcastSystemTools"),
            symbol: SystemToolsModule.networkSymbol, switchID: "systemTools",
            keywords: ["speed", "internet", "wifi", "networkQuality"],
            run: { $0.module(SystemToolsModule.self)?.testNetwork() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: switchID) { _ in
            AnyView(SudoTouchIDSettingsView(store: SudoTouchIDStore(files: .live)))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SystemToolsModule(context: context, system: .live)
    }
}
