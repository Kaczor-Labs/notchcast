import Foundation

/// Sends the Finder selection to the user's other Tailscale devices, one command per device.
enum TaildropAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "taildrop",
            title: String(localized: "Taildrop", table: "NotchcastTaildrop"),
            subtitle: String(
                localized: "Send the Finder selection to your other Tailscale devices.", table: "NotchcastTaildrop"),
            category: .filesDownloads),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        TaildropModule(context: context, environment: .live)
    }
}
