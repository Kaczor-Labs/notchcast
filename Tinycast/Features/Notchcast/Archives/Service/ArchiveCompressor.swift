// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchArchiveOperation and MediaSupport: write privately, publish exclusively.

import Darwin
import Foundation

/// One Finder selection into one archive beside it; every program call goes through `run`.
nonisolated struct ArchiveCompressor: Sendable {
    var locate: @Sendable (String) async -> URL?
    var run: @Sendable (URL, [String]) async throws -> ArchiveProcessResult

    /// The new archive; the private folder goes on every exit, and publishing on main lets a stop win.
    @concurrent
    func compress(_ plan: CompressionPlan) async throws -> URL {
        var tools: [URL] = []
        for choices in ArchiveCommandLine.compressTools(plan.format) { tools.append(try await find(choices)) }
        let files = FileManager.default
        let work = try files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: plan.folder, create: true)
        defer { try? files.removeItem(at: work) }
        let staged = work.appending(path: "Output." + plan.format.rawValue)
        var clones: URL?
        if plan.zipsClones {
            let folder = work.appending(path: "Items", directoryHint: .isDirectory)
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
            for input in plan.inputs {
                try Task.checkCancellation()
                try files.copyItem(at: input, to: folder.appending(path: input.lastPathComponent))
            }
            clones = folder
        }
        try Task.checkCancellation()
        let result = try await run(
            tools[0], ArchiveCommandLine.compress(plan, tools: tools, staged: staged, clones: clones))
        guard result.status == 0 else { throw ArchiveFailure.compressionFailed(ArchiveFailure.detail(result)) }
        return try await MainActor.run {
            try Task.checkCancellation()
            return try Self.publish(staged, plan: plan)
        }
    }

    /// Renames into the first free name; one taken meanwhile moves on to the next, never over it.
    static func publish(
        _ staged: URL, plan: CompressionPlan, renameExclusive: (URL, URL) -> Int32 = renameExclusive
    ) throws -> URL {
        // attributesOfItem does not follow a link, so a dangling one still counts as taken.
        let taken = { (name: String) in
            (try? FileManager.default.attributesOfItem(atPath: plan.folder.appending(path: name).path)) != nil
        }
        while true {
            let target = plan.folder.appending(path: ArchiveCompression.outputName(
                stem: plan.stem, format: plan.format, taken: taken))
            switch renameExclusive(staged, target) {
            case 0: return target
            case EEXIST: continue
            // exFAT and SMB lack RENAME_EXCL; moveItem also refuses a taken name, not atomically.
            case ENOTSUP, EINVAL:
                do {
                    try FileManager.default.moveItem(at: staged, to: target)
                    return target
                } catch CocoaError.fileWriteFileExists {
                    continue
                }
            case let code: throw ArchiveFailure.compressionFailed(String(cString: strerror(code)))
            }
        }
    }

    /// `renamex_np` with `RENAME_EXCL`: 0, else its errno.
    static func renameExclusive(_ from: URL, _ to: URL) -> Int32 {
        from.withUnsafeFileSystemRepresentation { from in
            to.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return EINVAL }
                return renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
    }

    static func kind(_ url: URL) -> ArchiveItemKind {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return .other }
        if values.isSymbolicLink == true { return .link }
        if values.isDirectory == true { return .folder }
        return values.isRegularFile == true ? .file : .other
    }

    static func isWritable(_ folder: URL) -> Bool { FileManager.default.isWritableFile(atPath: folder.path) }

    private func find(_ choices: [ArchiveTool]) async throws -> URL {
        for tool in choices { if let url = await locate(tool.name) { return url } }
        throw ArchiveFailure.missingTool(choices[0])
    }
}
