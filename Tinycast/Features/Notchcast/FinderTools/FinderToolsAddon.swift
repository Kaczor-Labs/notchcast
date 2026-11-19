import Foundation

enum FinderToolsAddon: NotchcastAddon {
    static let cutPasteSwitchID = "finderCutPaste"
    static let renameSwitchID = "finderRename"

    static let switches = [
        NotchcastSwitch(
            id: "finderCutPaste",
            title: String(localized: "Cut and paste in Finder", table: "NotchcastFinderTools"),
            subtitle: String(
                localized: "⌘X then ⌘V moves files instead of copying them.", table: "NotchcastFinderTools"),
            category: .macTweaks,
            requiredGrants: [.accessibility]
        ),
        NotchcastSwitch(
            id: "finderRename",
            title: String(localized: "Quick rename in Finder", table: "NotchcastFinderTools"),
            subtitle: String(
                localized: "⌃⌥⇧⌘R renames the selection without reaching for Return.", table: "NotchcastFinderTools"),
            category: .macTweaks,
            requiredGrants: [.accessibility]
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "finder-cut", name: String(localized: "Cut Files in Finder", table: "NotchcastFinderTools"),
            symbol: "scissors", switchID: "finderCutPaste", keywords: ["move", "cut"],
            run: { $0.module(FinderToolsModule.self)?.run(.cut) }),
        NotchcastCommand(
            slug: "finder-paste", name: String(localized: "Paste Files in Finder", table: "NotchcastFinderTools"),
            symbol: "doc.on.clipboard", switchID: "finderCutPaste", keywords: ["move", "paste"],
            run: { $0.module(FinderToolsModule.self)?.run(.paste) }),
        NotchcastCommand(
            slug: "finder-rename", name: String(localized: "Rename in Finder", table: "NotchcastFinderTools"),
            symbol: "pencil", switchID: "finderRename", keywords: ["rename", "file"],
            run: { $0.module(FinderToolsModule.self)?.run(.rename) }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        FinderToolsModule(context: context, system: .live)
    }
}
