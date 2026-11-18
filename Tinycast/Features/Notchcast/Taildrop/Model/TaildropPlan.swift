import Foundation

/// One selected item on its way out: itself, or the archive a folder travels as.
nonisolated struct TaildropUpload: Equatable, Sendable {
    let source: String
    let archive: String?

    var file: String { archive ?? source }
}

nonisolated enum TaildropPlan {
    /// `tailscale file cp` refuses a directory, so each folder is zipped into `scratch` first.
    static func uploads(_ items: [(path: String, isFolder: Bool)], scratch: String) -> [TaildropUpload] {
        var taken: Set<String> = []
        return items.map { item in
            guard item.isFolder else { return TaildropUpload(source: item.path, archive: nil) }
            let name = URL(filePath: item.path).lastPathComponent
            var archive = name + ".zip"
            var copy = 2
            while !taken.insert(archive).inserted {
                archive = "\(name) \(copy).zip"
                copy += 1
            }
            let url = URL(filePath: scratch).appending(path: archive)
            return TaildropUpload(source: item.path, archive: url.path(percentEncoded: false))
        }
    }

    /// Finder answers with file URLs; a folder's trailing slash goes, and anything remote is dropped.
    static func localPath(_ raw: String) -> String? {
        guard let url = raw.hasPrefix("/") ? URL(filePath: raw) : URL(string: raw), url.isFileURL else { return nil }
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.hasPrefix("/") ? path : nil
    }
}
