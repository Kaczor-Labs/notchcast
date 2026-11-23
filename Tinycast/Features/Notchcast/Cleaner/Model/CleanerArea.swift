// Adapted from Dragos Tugui's Peel, SpaceReport.swift @ 20230794 (GPL-3.0).
import Foundation

struct CleanerArea: Sendable, Equatable {
    let home: URL

    var root: URL { home.appending(path: "Library/Caches", directoryHint: .isDirectory) }

    func contains(_ item: URL) -> Bool {
        item.isFileURL && item == item.standardizedFileURL
            && item.deletingLastPathComponent().path == root.path
    }
}
