import Foundation

/// The add-on's keys in the `<bundle id>.notchcast` suite; the repo holds no path, so the file starts unset.
@MainActor
struct ThreadsPreferences {
    static let switchID = "threads"
    static let fileKey = "threads.waitsFile"
    static let shownKey = "threads.shownWaits"

    let defaults: UserDefaults

    var waitsFile: String? {
        get { defaults.string(forKey: Self.fileKey).flatMap { $0.isEmpty ? nil : $0 } }
        nonmutating set { defaults.set(newValue, forKey: Self.fileKey) }
    }

    var waitsURL: URL? { waitsFile.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } }

    var shown: ThreadsShown {
        get { ThreadsShown(ids: defaults.stringArray(forKey: Self.shownKey) ?? []) }
        nonmutating set { defaults.set(newValue.ids, forKey: Self.shownKey) }
    }
}

/// Reads the waits file off the main actor; a file no bigger than the cap and in the v1 shape, or nothing.
enum ThreadsFile {
    /// Far above any real document; a bigger file is not one.
    static let maximumSize = 4 << 20

    @concurrent
    static func read(_ url: URL?) async -> ThreadsRead {
        guard let url else { return .unset }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .missing
        }
        guard size <= maximumSize, let data = try? Data(contentsOf: url),
              let document = try? ThreadsDocument.decode(data) else { return .unreadable }
        return .loaded(document)
    }
}
