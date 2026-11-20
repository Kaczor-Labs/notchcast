import Foundation

/// The feed folder: `feed.json` is read, written by whatever syncs the Macs; `local.json` is this Mac's.
struct AgentFeedStore: Sendable {
    /// Far above any real feed; a bigger file is not one.
    static let maximumSize = 4 << 20

    var folder: URL

    var feedURL: URL { folder.appending(path: "feed.json") }
    var localURL: URL { folder.appending(path: "local.json") }

    func read() -> AgentFeedRead {
        let size = (try? feedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let size else { return FileManager.default.fileExists(atPath: feedURL.path) ? .unreadable : .missing }
        guard size <= Self.maximumSize, let data = try? Data(contentsOf: feedURL) else { return .unreadable }
        do {
            return .loaded(try AgentFeed.decode(data))
        } catch AgentFeedError.unknownVersion(let version) {
            return .unknownVersion(version)
        } catch {
            return .unreadable
        }
    }

    /// Atomic, so a reader on another process never sees half a file.
    func writeLocal(_ feed: AgentFeed) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try feed.encoded().write(to: localURL, options: .atomic)
    }
}
