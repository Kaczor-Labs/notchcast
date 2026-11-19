// notchcast-addon-order: 140
// notchcast-readme: Keyboard & Mouse: Paste Plain Text
import Foundation

enum PastePlainTextAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "pastePlain",
            title: String(localized: "Paste Plain Text", table: "NotchcastPastePlainText"),
            subtitle: String(
                localized: "Paste the clipboard's text without formatting; the clipboard stays as it was.",
                table: "NotchcastPastePlainText"),
            category: .keyboardMouse,
            defaultEnabled: false,
            requiredGrants: [.accessibility]
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "paste-plain-text", name: String(localized: "Paste Plain Text", table: "NotchcastPastePlainText"),
            symbol: "doc.plaintext", switchID: "pastePlain", keywords: ["unformatted", "clipboard", "rich text"],
            run: { $0.module(PastePlainTextModule.self)?.paste() }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        PastePlainTextModule(context: context, system: .live)
    }
}
