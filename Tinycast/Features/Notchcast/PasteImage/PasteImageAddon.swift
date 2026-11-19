// notchcast-addon-order: 180
import Foundation

enum PasteImageAddon: NotchcastAddon {
    static let switchID = "pasteImage"

    static let switches = [
        NotchcastSwitch(
            id: "pasteImage",
            title: String(localized: "Paste images as files in Finder", table: "NotchcastPasteImage"),
            subtitle: String(
                localized: "⌘V in a Finder window saves a copied image there as a PNG file.",
                table: "NotchcastPasteImage"),
            category: .filesDownloads,
            requiredGrants: [.accessibility]
        ),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        PasteImageModule(context: context, system: .live)
    }
}
