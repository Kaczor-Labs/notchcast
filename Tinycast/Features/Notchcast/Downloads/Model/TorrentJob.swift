import Foundation

/// One torrent the user asked for, from its first check to its last state.
nonisolated struct TorrentJob: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case findingPeers, downloading, sharing, finished, failed(String), cancelled

        var isActive: Bool { [.findingPeers, .downloading, .sharing].contains(self) }
    }

    let id: UUID
    let input: TorrentInput
    let infoHash: String
    var name: String
    var state: State = .findingPeers
    /// aria2c's id for the download now followed; a magnet's metadata job hands over to its real one.
    var gid: String?
    var completed: Int64 = 0
    var total: Int64 = 0
    var speed: Int64 = 0
    var peers = 0
    var seeders = 0
    /// When peers or progress were last seen; ten quiet minutes fail the job.
    var lastActivity: Date
    var files: [URL] = []

    init(id: UUID = UUID(), input: TorrentInput, infoHash: String, name: String, started: Date) {
        self.id = id
        self.input = input
        self.infoHash = infoHash
        self.name = name
        lastActivity = started
    }

    var fraction: Double? { total > 0 ? min(1, Double(completed) / Double(total)) : nil }

    var secondsLeft: Int64? { speed > 0 && total > completed ? (total - completed) / speed : nil }
}
