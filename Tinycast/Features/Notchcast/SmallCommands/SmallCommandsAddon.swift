// notchcast-addon-order: 70
// notchcast-readme: Launcher Extras: small commands for passwords, short links and AirDrop
import Foundation

enum SmallCommandsAddon: NotchcastAddon {
    static let switchID = "smallCommands"

    static let switches = [
        NotchcastSwitch(
            id: "smallCommands",
            title: String(localized: "Small Commands", table: "NotchcastSmallCommands"),
            subtitle: String(localized: "Passwords, short links and AirDrop.", table: "NotchcastSmallCommands"),
            category: .launcher,
            defaultEnabled: false
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "generate-password", name: String(localized: "Generate Password", table: "NotchcastSmallCommands"),
            symbol: SmallCommandsModule.Action.password.symbol, switchID: "smallCommands",
            keywords: ["random", "secure"], run: { $0.module(SmallCommandsModule.self)?.run(.password) }),
        NotchcastCommand(
            slug: "shorten-link", name: String(localized: "Shorten Link", table: "NotchcastSmallCommands"),
            symbol: SmallCommandsModule.Action.shorten.symbol, switchID: "smallCommands",
            keywords: ["url", "tinyurl"], run: { $0.module(SmallCommandsModule.self)?.run(.shorten) }),
        NotchcastCommand(
            slug: "airdrop-selection", name: String(localized: "AirDrop Selected Files", table: "NotchcastSmallCommands"),
            symbol: SmallCommandsModule.Action.airDrop.symbol, switchID: "smallCommands",
            keywords: ["share", "finder"], run: { $0.module(SmallCommandsModule.self)?.run(.airDrop) }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SmallCommandsModule(context: context, system: .live)
    }
}
