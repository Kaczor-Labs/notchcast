import Foundation

/// A program an engine runs; every one is the user's own install, never bundled.
nonisolated struct ArchiveTool: Equatable, Sendable {
    let name: String
    let installCommand: String

    static let hatchzip = ArchiveTool(name: "hatchzip", installCommand: "brew install xevrion/tap/hatchzip")
    static let bsdtar = ArchiveTool(name: "bsdtar", installCommand: "brew install libarchive")
    static let unar = ArchiveTool(name: "unar", installCommand: "brew install unar")
    static let lsar = ArchiveTool(name: "lsar", installCommand: "brew install unar")
    static let gzip = ArchiveTool(name: "gzip", installCommand: "brew install gzip")
    static let bzip2 = ArchiveTool(name: "bzip2", installCommand: "brew install bzip2")
    static let xz = ArchiveTool(name: "xz", installCommand: "brew install xz")
    static let zstd = ArchiveTool(name: "zstd", installCommand: "brew install zstd")
    static let shell = ArchiveTool(name: "sh", installCommand: "")
}

/// Every program call an extraction makes, as plain arguments.
nonisolated enum ArchiveCommandLine {
    /// The tool that lists the archive, then the one that extracts it.
    static func tools(_ engine: ArchiveEngine) -> (list: ArchiveTool?, extract: ArchiveTool) {
        switch engine {
        case .hatchzip: (.hatchzip, .hatchzip)
        case .bsdtar: (.bsdtar, .bsdtar)
        case .unar: (.lsar, .unar)
        case .gzip: (nil, .gzip)
        case .bzip2: (nil, .bzip2)
        case .xz: (nil, .xz)
        case .zstd: (nil, .zstd)
        }
    }

    static func list(_ engine: ArchiveEngine, archive: URL) -> [String]? {
        switch engine {
        case .hatchzip: ["list", archive.path]
        case .bsdtar: ["-tvf", archive.path]
        case .unar: ["-j", archive.path]
        case .gzip, .bzip2, .xz, .zstd: nil
        }
    }

    /// A single stream runs under `/bin/sh`, with every path a positional argument, never spliced in.
    static func extract(
        _ engine: ArchiveEngine, tool: URL, archive: URL, staging: URL, stem: String, inPlace: Bool
    ) -> [String] {
        switch engine {
        case .hatchzip:
            ["extract", archive.path, "-o", staging.path, "-q"] + (inPlace ? ["-y"] : ["--keep-archive"])
        case .bsdtar: ["-xf", archive.path, "-C", staging.path]
        case .unar: ["-o", staging.path, "-D", "-q", archive.path]
        case .gzip, .bzip2, .xz, .zstd:
            ["-c", #"exec "$0" -dc "$1" > "$2""#, tool.path, archive.path, staging.appending(path: stem).path]
        }
    }

    /// HatchZip's space plan for extracting in place, shown when keeping the archive does not fit.
    static func check(archive: URL, staging: URL) -> [String] { ["check", archive.path, "-o", staging.path] }

    /// Makes a stopped extraction's archive whole again, or only drops its progress when it was kept.
    static func restore(archive: URL, staging: URL) -> [String] { ["restore", archive.path, "-o", staging.path] }
}
