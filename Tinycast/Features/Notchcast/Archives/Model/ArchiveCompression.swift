// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's MediaSupport: the output name and its cut to 255 bytes.

import Foundation

/// What a Finder selection compresses to; the raw value is the file extension.
nonisolated enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip = "7z"
    case tarZstd = "tar.zst"
}

/// What a selected path is on disk; only the first three may be compressed.
nonisolated enum ArchiveItemKind: Sendable {
    case file, folder, link, other
}

/// One compression, worked out before any tool runs.
nonisolated struct CompressionPlan: Equatable, Sendable {
    let format: ArchiveFormat
    let inputs: [URL]
    /// Where the inputs sit and the archive lands.
    let folder: URL
    /// The archive's name before its extension: the one item's whole name, else the folder's.
    let stem: String
    /// The kind of a lone input; nil for several.
    let single: ArchiveItemKind?

    /// The name shown while it runs, before a free number is known.
    var label: String { stem + "." + format.rawValue }

    /// ditto zips a lone file or folder as is; several items, or a link it follows, go as clones.
    var zipsClones: Bool { format == .zip && (single == nil || single == .link) }
}

nonisolated enum ArchiveCompression {
    static let maxNameBytes = 255
    /// Room for ` 999`, as the reference keeps.
    static let numberBytes = 4

    static func plan(
        format: ArchiveFormat, selection: [URL], kind: (URL) -> ArchiveItemKind, isWritable: (URL) -> Bool
    ) throws(ArchiveFailure) -> CompressionPlan {
        var seen = Set<String>()
        let inputs = selection.filter(\.isFileURL).map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
        guard !inputs.isEmpty else { throw .nothingSelected }
        if let root = inputs.first(where: { $0.path == "/" }) { throw .notCompressible(root.path) }
        let folders = Set(inputs.map { $0.deletingLastPathComponent().path })
        guard folders.count == 1, let path = folders.first else { throw .severalFolders }
        let kinds = inputs.map(kind)
        if let index = kinds.firstIndex(of: .other) { throw .notCompressible(inputs[index].lastPathComponent) }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        guard isWritable(folder) else { throw .notWritable(folder.lastPathComponent) }
        let name = inputs.count == 1 ? inputs[0].lastPathComponent : folder.lastPathComponent
        return CompressionPlan(
            format: format, inputs: inputs, folder: folder, stem: cut(name, format: format),
            single: inputs.count == 1 ? kinds[0] : nil)
    }

    /// `stem.ext`, else `stem 2.ext`…: the number goes before the whole extension (`Trip 2.tar.zst`).
    static func outputName(stem: String, format: ArchiveFormat, taken: (String) -> Bool) -> String {
        ArchivePlacement.freeName(stem, keepsExtension: false) { taken($0 + "." + format.rawValue) }
            + "." + format.rawValue
    }

    /// Fits the name, its extension and a number in 255 bytes, never cutting through a character.
    static func cut(_ name: String, format: ArchiveFormat) -> String {
        let limit = maxNameBytes - format.rawValue.utf8.count - 1 - numberBytes
        guard name.utf8.count > limit else { return name }
        var result = ""
        var used = 0
        for character in name {
            let count = String(character).utf8.count
            guard used + count <= limit else { break }
            result.append(character)
            used += count
        }
        return result
    }
}
