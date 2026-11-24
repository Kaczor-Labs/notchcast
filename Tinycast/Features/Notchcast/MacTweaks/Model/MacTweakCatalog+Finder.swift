// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
enum MacTweakCatalog {
    static let finder: [MacTweak] = [
        preference("file-extensions", "AppleShowAllExtensions", domain: "NSGlobalDomain", restartFinder: true),
        preference("hidden-files", "AppleShowAllFiles", restartFinder: true),
        preference("path-bar", "ShowPathbar", restartFinder: true),
        preference("status-bar", "ShowStatusBar", restartFinder: true),
        preference("folders-first", "_FXSortFoldersFirst", restartFinder: true),
        preference("search-this-folder", "FXDefaultSearchScope", value: .string("SCcf"), restartFinder: true),
        preference("extension-warning", "FXEnableExtensionChangeWarning", value: .bool(false), restartFinder: true),
        preference("path-in-title", "_FXShowPosixPathInTitle", restartFinder: true),
        preference("network-ds-store", "DSDontWriteNetworkStores", domain: "com.apple.desktopservices"),
        preference("trash-30-days", "FXRemoveOldTrashItems", restartFinder: true),
        preference("save-locally", "NSDocumentSaveNewDocumentsToCloud", domain: "NSGlobalDomain", value: .bool(false)),
        preference("expanded-save", "NSNavPanelExpandedStateForSaveMode", domain: "NSGlobalDomain"),
        MacTweak(id: "show-library", group: .finder, changes: [.showLibrary]),
    ]

    private static func preference(
        _ id: MacTweak.ID, _ key: String, domain: String = "com.apple.finder",
        value: MacTweakValue = .bool(true), restartFinder: Bool = false
    ) -> MacTweak {
        MacTweak(id: id, group: .finder, changes: [.preference(.preference(domain: domain, key: key), value)],
                 restarts: restartFinder ? [.finder] : [])
    }
}
