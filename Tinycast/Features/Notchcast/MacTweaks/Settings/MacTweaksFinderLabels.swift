import Foundation

extension MacTweak {
    var finderTitle: LocalizedStringResource {
        switch id {
        case "file-extensions": LocalizedStringResource("Show file extensions", table: "NotchcastMacTweaks")
        case "hidden-files": LocalizedStringResource("Show hidden files", table: "NotchcastMacTweaks")
        case "path-bar": LocalizedStringResource("Show the path bar", table: "NotchcastMacTweaks")
        case "status-bar": LocalizedStringResource("Show the status bar", table: "NotchcastMacTweaks")
        case "folders-first": LocalizedStringResource("Keep folders above files", table: "NotchcastMacTweaks")
        case "search-this-folder": LocalizedStringResource("Search the current folder", table: "NotchcastMacTweaks")
        case "extension-warning":
            LocalizedStringResource("Skip the extension change warning", table: "NotchcastMacTweaks")
        case "path-in-title": LocalizedStringResource("Show the full path in the title bar", table: "NotchcastMacTweaks")
        case "network-ds-store":
            LocalizedStringResource("Stop .DS_Store files on network drives", table: "NotchcastMacTweaks")
        case "trash-30-days": LocalizedStringResource("Empty the Trash after 30 days", table: "NotchcastMacTweaks")
        case "save-locally": LocalizedStringResource("Save new documents on this Mac", table: "NotchcastMacTweaks")
        case "expanded-save": LocalizedStringResource("Expand Save dialogs", table: "NotchcastMacTweaks")
        case "show-library": LocalizedStringResource("Show the Library folder", table: "NotchcastMacTweaks")
        default: LocalizedStringResource(stringLiteral: id)
        }
    }

    var finderDetail: LocalizedStringResource? {
        switch id {
        case "network-ds-store": LocalizedStringResource("Takes effect after you log out.", table: "NotchcastMacTweaks")
        case "save-locally", "expanded-save":
            LocalizedStringResource("Takes effect when you reopen apps.", table: "NotchcastMacTweaks")
        case "show-library":
            LocalizedStringResource("Shows Library in your home folder.", table: "NotchcastMacTweaks")
        default: nil
        }
    }
}

extension MacTweakState {
    var unavailableReason: LocalizedStringResource? {
        switch self {
        case .applied, .notApplied, .partial: nil
        case .managed: LocalizedStringResource("Managed by a profile", table: "NotchcastMacTweaks")
        case .heldElsewhere(.thisMac): LocalizedStringResource("Set for this Mac only", table: "NotchcastMacTweaks")
        case .heldElsewhere(.everyApp): LocalizedStringResource("Set for every app", table: "NotchcastMacTweaks")
        case .heldElsewhere(.everyAccount): LocalizedStringResource("Set for every account", table: "NotchcastMacTweaks")
        case .unsupported: LocalizedStringResource("Unavailable on this macOS version", table: "NotchcastMacTweaks")
        case .unavailable: LocalizedStringResource("Couldn’t read setting", table: "NotchcastMacTweaks")
        }
    }
}
