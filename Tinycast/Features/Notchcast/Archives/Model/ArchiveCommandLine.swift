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
    static let ditto = ArchiveTool(name: "ditto", installCommand: "")
    static let sevenZip = ArchiveTool(name: "7zz", installCommand: "brew install sevenzip")
    static let p7zip = ArchiveTool(name: "7z", installCommand: "brew install sevenzip")
}

/// Every program call an extraction or a compression makes, as plain arguments.
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

    /// A single stream runs under `/bin/sh`, paths as positional arguments, its output capped.
    static func extract(
        _ engine: ArchiveEngine, tool: URL, archive: URL, staging: URL, stem: String, inPlace: Bool,
        outputBlocks: Int64
    ) -> [String] {
        switch engine {
        case .hatchzip:
            ["extract", archive.path, "-o", staging.path, "-q"] + (inPlace ? ["-y"] : ["--keep-archive"])
        case .bsdtar: ["-xf", archive.path, "-C", staging.path]
        case .unar: ["-o", staging.path, "-D", "-q", archive.path]
        case .gzip, .bzip2, .xz, .zstd:
            [
                "-c", #"ulimit -f "$3" && exec "$0" -dc "$1" > "$2""#, tool.path, archive.path,
                staging.appending(path: stem).path, String(outputBlocks),
            ]
        }
    }

    /// HatchZip's space plan for extracting in place, shown when keeping the archive does not fit.
    static func check(archive: URL, staging: URL) -> [String] { ["check", archive.path, "-o", staging.path] }

    /// Makes a stopped extraction's archive whole again, or only drops its progress when it was kept.
    static func restore(archive: URL, staging: URL) -> [String] { ["restore", archive.path, "-o", staging.path] }

    /// What a compression needs: each inner list is one tool, its first name the one to install.
    static func compressTools(_ format: ArchiveFormat) -> [[ArchiveTool]] {
        switch format {
        case .zip: [[.ditto]]
        case .sevenZip: [[.sevenZip, .p7zip]]
        case .tarZstd: [[.bsdtar], [.zstd]]
        }
    }

    /// Runs the first of `tools`; `clones` holds copies of the inputs when the plan zips clones.
    static func compress(_ plan: CompressionPlan, tools: [URL], staged: URL, clones: URL?) -> [String] {
        switch plan.format {
        case .zip:
            if let clones { return ["-c", "-k", "--sequesterRsrc", clones.path, staged.path] }
            return ["-c", "-k", "--sequesterRsrc"] + (plan.single == .folder ? ["--keepParent"] : [])
                + [plan.inputs[0].path, staged.path]
        case .sevenZip:
            return ["a", "-t7z", "-mx=9", "-snl", "-spd", "-bd", "-y", "--", staged.path] + plan.inputs.map(\.path)
        case .tarZstd:
            // bsdtar splits the program on spaces and reads \ escapes, so zstd's path is quoted.
            let zstd = tools[1].path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
            return ["--use-compress-program", "\"\(zstd)\"", "-cf", staged.path, "-C", plan.folder.path]
                + plan.inputs.map { "./" + $0.lastPathComponent }
        }
    }
}
