import Foundation

nonisolated struct ArchiveEntry: Equatable, Sendable {
    var path: String
    var size: Int64 = 0
    var isDirectory = false
    var isLink = false
}

/// What an engine says an archive holds, read before anything is written.
nonisolated struct ArchiveListing: Equatable, Sendable {
    var entries: [ArchiveEntry]
    /// Bytes once extracted.
    var expandedSize: Int64
    /// The archive's own size, every volume of a split set, when the engine reports it.
    var archiveSize: Int64?

    init(entries: [ArchiveEntry], expandedSize: Int64? = nil, archiveSize: Int64? = nil) {
        self.entries = entries
        self.expandedSize = expandedSize ?? entries.reduce(0) { $0 + $1.size }
        self.archiveSize = archiveSize
    }

    /// `hatchzip list`: a 10-wide size column, two spaces, the path; then a totals line.
    static func hatchzip(_ output: String) -> ArchiveListing {
        var entries: [ArchiveEntry] = []
        var expanded: Int64?
        var archive: Int64?
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.first?.isNumber == true {
                let parts = line.components(separatedBy: ", ")
                guard parts.count == 3, parts[1].hasSuffix(" uncompressed") else { continue }
                expanded = size(String(parts[1].dropLast(" uncompressed".count)))
                archive = size(parts[2].split(separator: " ").prefix(2).joined(separator: " "))
                continue
            }
            guard line.count > 12, line.dropFirst(10).hasPrefix("  ") else { continue }
            let column = line.prefix(10).trimmingCharacters(in: .whitespaces)
            var path = String(line.dropFirst(12))
            guard !(column == "Size" && path == "Name") else { continue }
            var entry = ArchiveEntry(path: path, size: size(column) ?? 0)
            if path.hasSuffix("/") {
                path.removeLast()
                entry.isDirectory = true
            } else if path.hasSuffix(" (symlink)") {
                path.removeLast(" (symlink)".count)
                entry.isLink = true
            } else if path.hasSuffix(")"), let link = path.range(of: " (link to ", options: .backwards) {
                path = String(path[..<link.lowerBound])
            }
            entry.path = path
            entries.append(entry)
        }
        return ArchiveListing(entries: entries, expandedSize: expanded, archiveSize: archive)
    }

    /// `bsdtar -tv`: mode, links, owner, group, size, month, day, time or year, then the name.
    static func bsdtar(_ output: String) -> ArchiveListing {
        let entries = output.split(whereSeparator: \.isNewline).compactMap { line -> ArchiveEntry? in
            var rest = Substring(line)
            var fields: [Substring] = []
            while fields.count < 8 {
                rest = rest.drop(while: \.isWhitespace)
                guard let end = rest.firstIndex(where: \.isWhitespace) else { return nil }
                fields.append(rest[..<end])
                rest = rest[end...]
            }
            var name = String(rest.drop(while: \.isWhitespace))
            guard let mode = fields[0].first, !name.isEmpty else { return nil }
            if mode == "l", let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            if mode != "l", let link = name.range(of: " link to ") { name = String(name[..<link.lowerBound]) }
            let isDirectory = mode == "d"
            if isDirectory, name.hasSuffix("/") { name.removeLast() }
            return ArchiveEntry(path: name, size: Int64(fields[4]) ?? 0, isDirectory: isDirectory, isLink: mode == "l")
        }
        return ArchiveListing(entries: entries)
    }

    /// `lsar -j`: The Unarchiver's own JSON listing.
    static func lsar(_ json: Data) throws -> ArchiveListing {
        let document = try JSONDecoder().decode(LsarDocument.self, from: json)
        return ArchiveListing(entries: document.contents.map {
            ArchiveEntry(path: $0.name, size: $0.size ?? 0, isDirectory: $0.isDirectory?.value ?? false,
                         isLink: $0.isLink?.value ?? false)
        })
    }

    /// HatchZip's sizes: powers of 1000, one decimal, `B` to `TB`.
    static func size(_ text: String) -> Int64? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let number = Double(parts[0]) else { return nil }
        let units = ["B": 1.0, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12]
        guard let unit = units[String(parts[1])] else { return nil }
        return Int64(number * unit)
    }
}

private nonisolated struct LsarDocument: Decodable {
    let contents: [Item]

    enum CodingKeys: String, CodingKey { case contents = "lsarContents" }

    struct Item: Decodable {
        let name: String
        let size: Int64?
        let isDirectory: Flag?
        let isLink: Flag?

        enum CodingKeys: String, CodingKey {
            case name = "XADFileName"
            case size = "XADFileSize"
            case isDirectory = "XADIsDirectory"
            case isLink = "XADIsLink"
        }
    }

    /// lsar writes its flags as numbers; a boolean is read too.
    struct Flag: Decodable {
        let value: Bool

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                value = flag
            } else {
                value = try container.decode(Int.self) != 0
            }
        }
    }
}
