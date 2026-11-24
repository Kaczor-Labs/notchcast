import Foundation

extension CleanerArea.Kind {
    var cleanerTitle: String {
        switch self {
        case .caches: String(localized: "App caches", table: "NotchcastCleaner")
        case .logs: String(localized: "Logs", table: "NotchcastCleaner")
        case .containerCaches: String(localized: "App containers", table: "NotchcastCleaner")
        case .browserCaches: String(localized: "Browser caches", table: "NotchcastCleaner")
        case .browserVersions: String(localized: "Old browser versions", table: "NotchcastCleaner")
        case .mailDownloads: String(localized: "Mail downloads", table: "NotchcastCleaner")
        case .homebrewLogs: String(localized: "Homebrew logs", table: "NotchcastCleaner")
        case .savedState: String(localized: "Saved app state", table: "NotchcastCleaner")
        }
    }
}

extension CleanerItem.Standing {
    var cleanerLabel: String {
        switch self {
        case .recommended: String(localized: "Recommended", table: "NotchcastCleaner")
        case .optional: String(localized: "Optional", table: "NotchcastCleaner")
        case .heldBack: String(localized: "Held back", table: "NotchcastCleaner")
        case .locked: String(localized: "Locked", table: "NotchcastCleaner")
        }
    }

    var cleanerDetail: String {
        switch self {
        case .recommended:
            String(localized: "Selected by default. You can put it back from the Trash.", table: "NotchcastCleaner")
        case .optional:
            String(localized: "Review this item before selecting it.", table: "NotchcastCleaner")
        case .heldBack(let reason), .locked(let reason):
            reason.cleanerDetail
        }
    }
}

private extension CleanerHoldBack {
    var cleanerDetail: String {
        switch self {
        case .protectedData:
            String(localized: "This location can contain protected app data.", table: "NotchcastCleaner")
        case .unsafePath:
            String(localized: "The path could not be checked safely.", table: "NotchcastCleaner")
        case .runningApp:
            String(localized: "Quit the app and scan again to include this item.", table: "NotchcastCleaner")
        case .runningProgram:
            String(localized: "A program is running from this item. Quit it and scan again.",
                   table: "NotchcastCleaner")
        case .holdsRepository:
            String(localized: "A code repository inside can contain work you want to keep.",
                   table: "NotchcastCleaner")
        case .openFile:
            String(localized: "An open file is in use. Close it and scan again.", table: "NotchcastCleaner")
        case .recentWrite:
            String(localized: "This was modified in the last 15 minutes.", table: "NotchcastCleaner")
        case .recentSavedState:
            String(localized: "Saved app state stays in place for at least 31 days.", table: "NotchcastCleaner")
        case .mailDownloadMayContainEdits:
            String(localized: "Mail downloads can contain edits you want to keep.", table: "NotchcastCleaner")
        case .activeBrowserVersion:
            String(localized: "The browser may still need this version.", table: "NotchcastCleaner")
        case .unreadable:
            String(localized: "Cleaner could not read everything needed to verify this item.",
                   table: "NotchcastCleaner")
        case .scanLimit:
            String(localized: "The scan could not finish checking this item.", table: "NotchcastCleaner")
        case .locked(let protection):
            protection.lockReason ?? String(localized: "This item is locked.", table: "NotchcastCleaner")
        }
    }
}
