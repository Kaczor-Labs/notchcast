import SwiftUI

enum SystemToolsAddon: NotchcastAddon {
    static let switchID = "systemTools"

    static let switches = [
        NotchcastSwitch(
            id: "systemTools",
            title: String(localized: "System tools", table: "NotchcastSystemTools"),
            subtitle: String(
                localized: "Kill a process, test your network, copy IP addresses and Wi-Fi passwords, and Touch ID for sudo.",
                table: "NotchcastSystemTools"),
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
        NotchcastCommand(
            slug: "wifi-password", name: String(localized: "Copy Wi-Fi Password", table: "NotchcastSystemTools"),
            symbol: WiFiNetworkSession.symbol, switchID: "systemTools",
            keywords: ["wifi", "wi-fi", "password", "network", "ssid"],
            run: { $0.module(SystemToolsModule.self)?.copyWiFiPassword() }),
        NotchcastCommand(
            slug: "local-ip", name: String(localized: "Copy Local IP Address", table: "NotchcastSystemTools"),
            symbol: SystemToolsModule.localSymbol, switchID: "systemTools",
            keywords: ["ip", "address", "lan", "local", "network"],
            run: { $0.module(SystemToolsModule.self)?.copyLocalAddress() }),
        NotchcastCommand(
            slug: "public-ip", name: String(localized: "Copy Public IP Address", table: "NotchcastSystemTools"),
            symbol: SystemToolsModule.publicSymbol, switchID: "systemTools",
            keywords: ["ip", "address", "public", "external", "wan"],
            run: { $0.module(SystemToolsModule.self)?.copyPublicAddress() }),
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
