// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift and Leftover.swift @ 20230794 (GPL-3.0).
import Foundation

enum CleanerPolicy {
    static let recentWrite: TimeInterval = 15 * 60

    static func appKey(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func isExcluded(_ name: String, ownNames: Set<String>) -> Bool {
        [".ds_store", ".localized"].contains(name.lowercased())
            || CleanerProtectedPaths.isAppleCache(name)
            || ownNames.contains(appKey(name))
    }

    static func protection(for file: CleanerFile, in area: CleanerArea) -> CleanerHoldBack? {
        let facts = file.facts
        guard !facts.isSymbolicLink, facts.isDirectory || file.isRegularFile else { return .unsafePath }
        guard facts.isOwnedByCurrentUser else { return .locked(.notOwned) }
        let result = UninstallProtectionRules.classify(
            facts, environment: UninstallEnvironment(home: area.home.path, hasFullDiskAccess: true))
        return result.isRemovable ? nil : .locked(result)
    }
}
