// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift and Leftover.swift @ 20230794 (GPL-3.0).
import Foundation

enum CleanerPolicy {
    static let recentWrite: TimeInterval = 15 * 60

    static func appKey(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func groupOwner(_ name: String) -> String {
        var components = name.split(separator: ".")
        if let first = components.first, first.count == 10, first.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            components.removeFirst()
        }
        if let first = components.first, ["group", "groups", "systemgroup"].contains(first.lowercased()) {
            components.removeFirst()
        }
        return components.joined(separator: ".")
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
