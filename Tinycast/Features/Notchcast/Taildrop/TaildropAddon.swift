// notchcast-addon-order: 165
// notchcast-readme: Clipboard & Files: Taildrop the Finder selection to another of your devices
// notchcast-new-switch-ids: taildrop
import Foundation

enum TaildropAddon: NotchcastAddon {
    static let switchID = "taildrop"

    static let switches = [
        NotchcastSwitch(
            id: "taildrop",
            title: String(localized: "Taildrop", table: "NotchcastTaildrop"),
            subtitle: String(
                localized: "Send the Finder selection to another of your devices with Tailscale.",
                table: "NotchcastTaildrop"),
            category: .files,
            defaultEnabled: false
        ),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        TaildropModule(context: context, system: .live)
    }
}
