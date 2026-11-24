// notchcast-addon-order: 170
// notchcast-readme: Clipboard & Files: move files in Finder with ⌘X and ⌘V and rename them in the launcher
// notchcast-system-keys: ⌘X ⌘V
import Foundation

enum FinderToolsAddon: NotchcastAddon {
    static let cutPasteSwitchID = "finderCutPaste"

    static let switches = [
        NotchcastSwitch(
            id: "finderCutPaste",
            title: String(localized: "Cut and paste in Finder", table: "NotchcastFinderTools"),
            subtitle: String(
                localized: "⌘X then ⌘V moves files instead of copying them.", table: "NotchcastFinderTools"),
            category: .finder,
            requiredGrants: [.accessibility],
            settingsTitle: String(localized: "Cut and paste", table: "NotchcastFinderTools")
        ),
        NotchcastSwitch(
            id: "finderRename",
            title: String(localized: "Quick rename in Finder", table: "NotchcastFinderTools"),
            subtitle: String(
                localized: "Rename the selected file or folder from the launcher or with a shortcut you choose.",
                table: "NotchcastFinderTools"),
            category: .finder,
            requiredGrants: [.accessibility],
            settingsTitle: String(localized: "Quick rename", table: "NotchcastFinderTools")
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "finder-rename", name: String(localized: "Rename in Finder", table: "NotchcastFinderTools"),
            symbol: "pencil", switchID: "finderRename", keywords: ["rename", "file"],
            run: { $0.module(FinderToolsModule.self)?.rename() }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        FinderToolsModule(context: context, system: .live)
    }
}
