import Foundation
import OSLog

/// The add-on's keys in the `<bundle id>.notchcast` suite; with no file chosen, t3chad's own path is read.
@MainActor
struct ThreadsPreferences {
    static let switchID = "threads"
    static let fileKey = "threads.waitsFile"
    static let shownKey = "threads.shownWaits"

    let defaults: UserDefaults
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    /// The file the user chose in Settings, if any.
    var waitsFile: String? {
        get { defaults.string(forKey: Self.fileKey).flatMap { $0.isEmpty ? nil : $0 } }
        nonmutating set { defaults.set(newValue, forKey: Self.fileKey) }
    }

    var waitsURL: URL {
        waitsFile.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? ThreadsDocument.defaultURL(home: home)
    }

    var shown: ThreadsShown {
        get { ThreadsShown(ids: defaults.stringArray(forKey: Self.shownKey) ?? []) }
        nonmutating set { defaults.set(newValue.ids, forKey: Self.shownKey) }
    }
}

/// Reads the waits file off the main actor; a file no bigger than the cap and in the v1 shape, or nothing.
enum ThreadsFile {
    /// Far above any real document; a bigger file is not one.
    static let maximumSize = 4 << 20

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "Threads")

    @concurrent
    static func read(_ url: URL) async -> ThreadsRead {
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
            return unreadable(error.localizedDescription)
        }
        guard let size else {
            return FileManager.default.fileExists(atPath: url.path) ? unreadable("it has no size") : .missing
        }
        guard size <= maximumSize else { return unreadable("\(size) bytes is over the cap") }
        do {
            return .loaded(try ThreadsDocument.decode(Data(contentsOf: url)))
        } catch let error as CocoaError {
            return unreadable(error.localizedDescription)
        } catch {
            return unreadable(String(describing: error))
        }
    }

    nonisolated private static func unreadable(_ reason: String) -> ThreadsRead {
        logger.error("Could not read the waits file: \(reason, privacy: .public)")
        return .unreadable
    }
}
