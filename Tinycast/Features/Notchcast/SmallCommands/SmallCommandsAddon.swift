import Foundation

enum SmallCommandsAddon: NotchcastAddon {
    static let switchID = "smallCommands"

    static let switches = [
        NotchcastSwitch(
            id: "smallCommands",
            title: String(localized: "Small Commands", table: "NotchcastSmallCommands"),
            subtitle: String(
                localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.",
                table: "NotchcastSmallCommands"),
            category: .launcher,
            defaultEnabled: false,
            requiredGrants: [.accessibility]
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
            slug: "switch-noise-control", name: String(localized: "Switch Noise Control", table: "NotchcastSmallCommands"),
            symbol: SmallCommandsModule.Action.noise.symbol, switchID: "smallCommands",
            keywords: ["airpods", "transparency", "anc"], run: { $0.module(SmallCommandsModule.self)?.run(.noise) }),
        NotchcastCommand(
            slug: "airdrop-selection", name: String(localized: "AirDrop Selected Files", table: "NotchcastSmallCommands"),
            symbol: SmallCommandsModule.Action.airDrop.symbol, switchID: "smallCommands",
            keywords: ["share", "finder"], run: { $0.module(SmallCommandsModule.self)?.run(.airDrop) }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SmallCommandsModule(context: context, system: .live)
    }
}
