import Foundation

/// Why an archive is refused before anything is written.
nonisolated enum ArchiveRefusal: Equatable, Sendable {
    case absolutePath(String)
    case parentPath(String)
    case driveLetter(String)
    case caseCollision(String, String)
    case underLink(String)
    case expansion(Int64)
    case unreadableListing

    var message: String {
        switch self {
        case .absolutePath(let path):
            String(localized: "Refused: \(path) is an absolute path.", table: "NotchcastArchives")
        case .parentPath(let path):
            String(localized: "Refused: \(path) points outside the folder.", table: "NotchcastArchives")
        case .driveLetter(let path):
            String(localized: "Refused: \(path) names a drive.", table: "NotchcastArchives")
        case .caseCollision(let first, let second):
            String(localized: "Refused: \(first) and \(second) differ only in case.", table: "NotchcastArchives")
        case .underLink(let path):
            String(localized: "Refused: \(path) is inside a linked folder.", table: "NotchcastArchives")
        case .expansion(let bytes):
            String(
                localized: "Refused: it would expand to \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).",
                table: "NotchcastArchives")
        case .unreadableListing:
            String(localized: "Refused: its file list cannot be read safely.", table: "NotchcastArchives")
        }
    }
}

/// Notchcast's own listing check, on top of whatever the engine checks itself.
nonisolated enum ArchiveSafety {
    /// Over both limits is a likely bomb: more than 5 GB out, and more than 1000 times the archive.
    static let expansionFloor: Int64 = 5_000_000_000
    static let expansionRatio: Int64 = 1000

    /// The most an unlisted single file may write, in the 1024-byte blocks macOS's `ulimit -f` counts.
    static func outputBlocks(archiveSize: Int64) -> Int64 {
        max(expansionFloor, expansionRatio.multipliedReportingOverflow(by: archiveSize).partialValue) / 1024
    }

    static func refusal(for listing: ArchiveListing, archiveSize: Int64) -> ArchiveRefusal? {
        if listing.isMalformed { return .unreadableListing }
        let size = listing.archiveSize ?? archiveSize
        if listing.expandedSize > expansionFloor, listing.expandedSize / max(size, 1) > expansionRatio {
            return .expansion(listing.expandedSize)
        }
        let links = Set(listing.entries.filter(\.isLink).map { components($0.path).joined(separator: "/") })
        var folded: [String: String] = [:]
        for entry in listing.entries {
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            if path.hasPrefix("/") { return .absolutePath(entry.path) }
            if let first = path.first, first.isASCII, first.isLetter, path.dropFirst().first == ":" {
                return .driveLetter(entry.path)
            }
            let parts = components(path)
            if parts.contains("..") { return .parentPath(entry.path) }
            if let target = entry.hardLinkTarget?.replacingOccurrences(of: "\\", with: "/") {
                if target.hasPrefix("/") { return .absolutePath(target) }
                if components(target).contains("..") { return .parentPath(target) }
            }
            for end in parts.indices {
                let prefix = parts[...end].joined(separator: "/")
                if end < parts.count - 1, links.contains(prefix) { return .underLink(entry.path) }
                // APFS folds case and Unicode form, so two such names land on one file.
                let key = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let other = folded[key], other != prefix { return .caseCollision(other, prefix) }
                folded[key] = prefix
            }
        }
        return nil
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "." }
    }
}
