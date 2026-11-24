// Adapted from Dragos Tugui's Peel, Leftover.swift and RemovalGuard.swift @ 20230794 (GPL-3.0).

enum CleanerHoldBack: Error, Equatable, Sendable {
    case protectedData
    case unsafePath
    case runningApp
    case openFile
    case recentWrite
    case recentSavedState
    case mailDownloadMayContainEdits
    case activeBrowserVersion
    case unreadable
    case scanLimit
    case locked(UninstallProtection)
}
