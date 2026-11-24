// notchcast-addon-order: 160
// notchcast-readme: Clipboard & Files: Copy Path for Finder files, browser links and documents
import Foundation

enum CopyPathAddon: NotchcastAddon {
    static let switchID = "copyPath"

    static let switches = [
        NotchcastSwitch(
            id: "copyPath",
            title: String(localized: "Copy Path", table: "NotchcastCopyPath"),
            subtitle: String(
                localized: "Copy the Finder selection, the browser link or the front document's path.",
                table: "NotchcastCopyPath"),
            category: .clipboard,
            defaultEnabled: false
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "copy-path", name: String(localized: "Copy Path", table: "NotchcastCopyPath"),
            symbol: CopyPathModule.symbol, switchID: "copyPath",
            keywords: ["finder", "file", "folder", "url", "link", "document"],
            run: { $0.module(CopyPathModule.self)?.run() }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        CopyPathModule(context: context, system: .live)
    }
}
