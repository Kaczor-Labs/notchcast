import Foundation

/// How one poll of aria2c moves a job; pure, so a harness drives it with statuses and a clock.
nonisolated enum TorrentJobPolicy {
    static let quietLimit: TimeInterval = 600

    static func advance(_ job: TorrentJob, with status: TorrentStatus, now: Date, keepSharing: Bool,
                        destination: URL) -> TorrentJob {
        guard job.state.isActive else { return job }
        var next = job
        if let follower = status.followedBy?.first {
            next.gid = follower
            next.lastActivity = now
            return next
        }
        if let name = status.bittorrent?.info?.name, !name.isEmpty { next.name = name }
        if status.completed > job.completed || status.peers > 0 { next.lastActivity = now }
        next.completed = status.completed
        next.total = status.total
        next.speed = status.speed
        next.peers = status.peers
        next.seeders = status.seeders
        let done = status.total > 0 && status.completed >= status.total
        if done, job.files.isEmpty { next.files = inside(destination, status.files?.map(\.path) ?? []) }
        switch status.status {
        case "error":
            next.state = .failed(status.errorMessage.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "aria2c stopped this download.", table: "NotchcastDownloads"))
        case "removed":
            next.state = .cancelled
        case "complete":
            next.state = .finished
        default:
            if done || status.isSeeding {
                next.state = keepSharing ? .sharing : .downloading
            } else if now.timeIntervalSince(next.lastActivity) >= quietLimit {
                next.state = .failed(String(localized: "No peers found in 10 minutes.", table: "NotchcastDownloads"))
            } else {
                next.state = status.completed > 0 || status.peers > 0 ? .downloading : .findingPeers
            }
        }
        next.speed = next.state.isActive ? next.speed : 0
        return next
    }

    /// aria2c names every file it wrote; only those inside the destination are ever reported.
    static func inside(_ destination: URL, _ paths: [String]) -> [URL] {
        let root = destination.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var seen = Set<String>()
        return paths.compactMap { path in
            guard path.hasPrefix("/") else { return nil }
            let file = URL(filePath: path).standardizedFileURL
            guard file.path.hasPrefix(prefix), seen.insert(file.path).inserted else { return nil }
            return file
        }
    }
}
