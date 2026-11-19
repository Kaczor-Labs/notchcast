import Foundation

/// The program that extracts an archive: HatchZip first, the user's own tools for the rest.
nonisolated enum ArchiveEngine: String, Sendable {
    case hatchzip
    case bsdtar
    case unar
    case gzip
    case bzip2
    case xz
    case zstd

    /// One compressed file with no archive inside: it decompresses to a single file named `stem`.
    var isSingleStream: Bool { [.gzip, .bzip2, .xz, .zstd].contains(self) }
}

/// What a file name says about an archive: which engine reads it and the name its contents take.
nonisolated struct ArchiveRoute: Equatable, Sendable {
    let engine: ArchiveEngine
    /// The name without its archive extensions, as Archive Utility names the folder.
    let stem: String

    /// Longest suffix first, so `.tar.gz` wins over `.gz` and `.tar.zst` over `.zst`.
    private static let suffixes: [(String, ArchiveEngine)] = [
        (".tar.bz2", .hatchzip), (".tar.zst", .bsdtar), (".tar.gz", .hatchzip), (".tar.xz", .hatchzip),
        (".cpio", .bsdtar), (".sitx", .unar), (".tbz2", .hatchzip), (".tzst", .bsdtar),
        (".arc", .unar), (".arj", .unar), (".bz2", .bzip2), (".cab", .bsdtar), (".iso", .bsdtar),
        (".lha", .unar), (".lzh", .unar), (".pkg", .bsdtar), (".rar", .hatchzip), (".sit", .unar),
        (".tar", .hatchzip), (".tbz", .hatchzip), (".tgz", .hatchzip), (".txz", .hatchzip),
        (".xar", .bsdtar), (".zip", .hatchzip), (".zoo", .unar), (".zst", .zstd),
        (".7z", .hatchzip), (".gz", .gzip), (".xz", .xz), (".z", .unar),
    ]

    /// Extensions Notchcast asks to open by default; installers and disk images keep their own apps.
    static let defaultExtensions = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz", "xz", "txz", "zst", "tzst", "001",
        "cab", "xar", "cpio", "sit", "sitx", "Z",
    ]

    init(engine: ArchiveEngine, stem: String) {
        self.engine = engine
        self.stem = stem
    }

    init?(fileName: String) {
        let lower = fileName.lowercased()
        let last = lower.split(separator: ".").last.map(String.init) ?? ""
        let base = String(fileName.dropLast(last.count + 1))
        if lower.contains("."), !base.isEmpty, last.count == 3, last.allSatisfy(\.isASCIIDigit) {
            // A byte-split volume (`game.7z.001`); HatchZip takes any part's name.
            self.init(engine: .hatchzip, stem: ArchiveRoute(fileName: base)?.stem ?? base)
            return
        }
        if !base.isEmpty, last.count == 3, last.hasPrefix("r"), last.dropFirst().allSatisfy(\.isASCIIDigit) {
            self.init(engine: .hatchzip, stem: base)
            return
        }
        guard let (suffix, engine) = Self.suffixes.first(where: { lower.hasSuffix($0.0) }),
            lower.count > suffix.count
        else { return nil }
        var stem = String(fileName.dropLast(suffix.count))
        if suffix == ".rar", let part = Self.volumePart(stem) { stem = String(stem.dropLast(part)) }
        guard !stem.isEmpty else { return nil }
        self.init(engine: engine, stem: stem)
    }

    /// The length of a trailing `.partN` on a RAR volume's stem, so the set gets one folder name.
    private static func volumePart(_ stem: String) -> Int? {
        guard let dot = stem.lastIndex(of: ".") else { return nil }
        let tail = stem[stem.index(after: dot)...].lowercased()
        guard tail.hasPrefix("part"), tail.count > 4, tail.dropFirst(4).allSatisfy(\.isASCIIDigit),
            dot > stem.startIndex
        else { return nil }
        return tail.count + 1
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
