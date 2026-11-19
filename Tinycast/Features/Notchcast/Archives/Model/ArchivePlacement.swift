import Foundation

/// Where extracted items land, as Archive Utility does it, never over an existing name.
nonisolated enum ArchivePlacement: Equatable, Sendable {
    /// The one top-level item moves beside the archive under `name`.
    case item(String, name: String)
    /// Several items stay together in a new folder beside the archive.
    case folder(name: String)
    case empty

    static func plan(items: [String], stem: String, taken: (String) -> Bool) -> ArchivePlacement {
        switch items.count {
        case 0: .empty
        case 1: .item(items[0], name: freeName(items[0], keepsExtension: true, taken: taken))
        default: .folder(name: freeName(stem, keepsExtension: false, taken: taken))
        }
    }

    /// `name`, else `name 2`, `name 3`…; a file keeps its extension last (`notes 2.txt`).
    static func freeName(_ name: String, keepsExtension: Bool, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let dot = keepsExtension ? name.lastIndex(of: ".").flatMap { $0 > name.startIndex ? $0 : nil } : nil
        let base = dot.map { String(name[..<$0]) } ?? name
        let suffix = dot.map { String(name[$0...]) } ?? ""
        var number = 2
        while taken("\(base) \(number)\(suffix)") { number += 1 }
        return "\(base) \(number)\(suffix)"
    }
}
