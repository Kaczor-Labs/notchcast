import Foundation

/// What a torrent job hands the engine: a magnet link or a checked `.torrent` file.
enum TorrentSource: Equatable, Sendable {
    case magnet(String)
    case torrent(Data)
}

/// One running engine; `Aria2Session` is the real one, the harnesses pass a fake.
protocol TorrentSession: AnyObject, Sendable {
    /// False once the engine's process has exited.
    var isAlive: Bool { get }
    func add(_ source: TorrentSource, options: [String: String]) async throws -> String
    func status(_ gid: String) async throws -> TorrentStatus
    /// Stops the download and forgets it; a gid aria2c no longer knows is not an error.
    func remove(_ gid: String) async
    func stop() async
}

/// The one error a session start throws when the user has no aria2c.
struct TorrentEngineMissing: LocalizedError {
    var errorDescription: String? { String(localized: "aria2c not found", table: "NotchcastDownloads") }
}

/// aria2c's own answer to one call; it fails that job alone.
struct Aria2Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
