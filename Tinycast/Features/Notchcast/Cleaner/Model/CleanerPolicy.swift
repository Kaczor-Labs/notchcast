// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift, Leftover.swift and FileSize.swift @ 20230794 (GPL-3.0).
// The maker's names follow Peel's Naming.swift and InstalledApp.swift @ 20230794 (GPL-3.0).
import Foundation

enum CleanerPolicy {
    static let recentWrite: TimeInterval = 15 * 60

    static func appKey(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let sharedDomains: Set<String> = [
        "com.github", "io.github", "com.gitlab", "io.gitlab", "org.sourceforge", "net.sourceforge", "com.googlecode",
        "uk.co", "uk.org", "uk.ac", "au.com", "au.net", "au.org", "jp.co", "jp.ne", "jp.or", "nz.co", "kr.co",
        "za.co", "il.co", "in.co", "br.com", "cn.com", "tw.com", "hk.com", "sg.com", "mx.com", "ar.com", "tr.com",
        "com.electron", "com.yourcompany", "com.todesktop", "com.install4j"
    ]

    // A maker's folder holds its apps' caches, under its name or domain, as Logs/jetbrains.com.
    static func makerNames(of identifier: String) -> [String] {
        var folded = identifier.lowercased()
        if folded.hasPrefix("maccatalyst.") { folded.removeFirst("maccatalyst.".count) }
        let components = folded.split(separator: ".")
        guard components.count >= 3 else { return [] }
        let isShared = sharedDomains.contains(components.prefix(2).joined(separator: "."))
        guard !isShared || components.count >= 4 else { return [] }
        let domain = components.prefix(isShared ? 3 : 2)
        return [String(domain.last ?? ""), domain.joined(separator: "."), domain.reversed().joined(separator: ".")]
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

    static let repositoryMarkers: Set<String> = [".git", ".hg", ".svn", ".jj", ".pijul", "_darcs"]

    // A move to the Trash never follows a link inside the row, so only the row must be a real item.
    static func protection(for file: CleanerFile, in area: CleanerArea, isRow: Bool = true) -> CleanerHoldBack? {
        let facts = file.facts
        if isRow, facts.isSymbolicLink || !(facts.isDirectory || file.isRegularFile) { return .unsafePath }
        guard facts.isOwnedByCurrentUser else { return .locked(.notOwned) }
        let result = UninstallProtectionRules.classify(
            facts, environment: UninstallEnvironment(home: area.home.path, hasFullDiskAccess: true))
        return result.isRemovable ? nil : .locked(result)
    }
}
