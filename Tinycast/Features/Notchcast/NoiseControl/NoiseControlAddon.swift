// notchcast-new-switch-ids: noiseControl
import Foundation

enum NoiseControlAddon: NotchcastAddon {
    static let switchID = "noiseControl"

    static let switches = [
        NotchcastSwitch(
            id: "noiseControl",
            title: String(localized: "AirPods Noise Control", table: "NotchcastNoiseControl"),
            subtitle: String(
                localized: "Switch AirPods and Beats listening modes through the Sound menu in the menu bar.",
                table: "NotchcastNoiseControl"),
            category: .displaySound,
            defaultEnabled: false,
            requiredGrants: [.accessibility]
        ),
    ]

    private static let table: [(slug: String, request: NoiseControlRequest, keywords: [String])] = [
        (slug: "noise-cancellation", request: .set(.noiseCancellation), keywords: ["anc", "airpods", "beats"]),
        (slug: "transparency", request: .set(.transparency), keywords: ["airpods", "beats", "listening"]),
        (slug: "adaptive", request: .set(.adaptive), keywords: ["airpods", "adaptive audio", "listening"]),
        (slug: "noise-control-off", request: .set(.off), keywords: ["airpods", "beats", "listening"]),
        (slug: "cycle-noise-control", request: .cycle, keywords: ["airpods", "beats", "listening", "next"]),
    ]

    static let commands = table.map { row in
        NotchcastCommand(
            slug: row.slug, name: row.request.title, symbol: row.request.symbol, switchID: switchID,
            keywords: row.keywords, run: { $0.module(NoiseControlModule.self)?.run(row.request) })
    }

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        NoiseControlModule(
            context: context, system: .live,
            commandIDs: table.map { (id: NotchcastCommand.idPrefix + $0.slug, request: $0.request) })
    }
}
