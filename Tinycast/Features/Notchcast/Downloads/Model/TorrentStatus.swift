import Foundation

/// aria2c's `tellStatus` answer, which writes every number as a string.
nonisolated struct TorrentStatus: Decodable, Equatable, Sendable {
    var status: String
    var completedLength = "0"
    var totalLength = "0"
    var downloadSpeed = "0"
    var connections = "0"
    var numSeeders: String?
    var seeder: String?
    var errorMessage: String?
    var followedBy: [String]?
    var files: [File]?
    var bittorrent: BitTorrent?

    struct File: Decodable, Equatable, Sendable { var path: String }
    struct BitTorrent: Decodable, Equatable, Sendable { var info: Info? }
    struct Info: Decodable, Equatable, Sendable { var name: String? }

    init(status: String, completed: Int64 = 0, total: Int64 = 0, speed: Int64 = 0, connections: Int = 0,
         seeders: Int = 0, isSeeding: Bool = false, error: String? = nil, followedBy: [String]? = nil,
         files: [String] = [], name: String? = nil) {
        self.status = status
        completedLength = String(completed)
        totalLength = String(total)
        downloadSpeed = String(speed)
        self.connections = String(connections)
        numSeeders = String(seeders)
        seeder = isSeeding ? "true" : "false"
        errorMessage = error
        self.followedBy = followedBy
        self.files = files.map(File.init)
        bittorrent = BitTorrent(info: Info(name: name))
    }

    var completed: Int64 { Int64(completedLength) ?? 0 }
    var total: Int64 { Int64(totalLength) ?? 0 }
    var speed: Int64 { Int64(downloadSpeed) ?? 0 }
    var peers: Int { Int(connections) ?? 0 }
    var seeders: Int { numSeeders.flatMap { Int($0) } ?? 0 }
    var isSeeding: Bool { seeder == "true" }
}
