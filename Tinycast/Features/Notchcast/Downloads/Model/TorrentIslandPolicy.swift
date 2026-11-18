import Foundation

/// What the island shows for the torrent jobs; pure, so a harness drives it with job lists.
nonisolated struct TorrentIslandPolicy: Sendable {
    struct Progress: Equatable, Sendable {
        var text: String
        var fraction: Double?
    }

    struct Update: Equatable, Sendable {
        var progress: Progress?
        var finished: [TorrentJob] = []
        var failed: [TorrentJob] = []
    }

    private var reported: Set<UUID> = []

    mutating func update(_ jobs: [TorrentJob]) -> Update {
        var update = Update()
        for job in jobs where !reported.contains(job.id) {
            switch job.state {
            case .finished: update.finished.append(job)
            case .failed: update.failed.append(job)
            case .cancelled: break
            default: continue
            }
            reported.insert(job.id)
        }
        reported.formIntersection(jobs.map(\.id))
        let running = jobs.filter { [.findingPeers, .downloading].contains($0.state) }
        guard let first = running.first else { return update }
        let total = running.reduce(Int64(0)) { $0 + $1.total }
        let fraction = total > 0 ? Double(running.reduce(Int64(0)) { $0 + $1.completed }) / Double(total) : nil
        let title = running.count > 1
            ? String(localized: "\(running.count) torrents", table: "NotchcastDownloads") : Self.short(first.name)
        update.progress = Progress(text: Self.line(title: title, fraction: fraction, speed: running.reduce(0) { $0 + $1.speed },
                                     secondsLeft: running.compactMap(\.secondsLeft).max(),
                                     findingPeers: running.allSatisfy { $0.state == .findingPeers }), fraction: fraction)
        return update
    }

    /// "ubuntu.iso · 42% · 3.1 MB/s · 2 min left", dropping each part aria2c cannot know yet.
    static func line(title: String, fraction: Double?, speed: Int64, secondsLeft: Int64?, findingPeers: Bool) -> String {
        guard !findingPeers else {
            return String(localized: "\(title) · Finding peers", table: "NotchcastDownloads")
        }
        var parts = [title]
        if let fraction { parts.append("\(Int(fraction * 100))%") }
        if speed > 0 { parts.append(speed.formatted(.byteCount(style: .file)) + "/s") }
        if let secondsLeft {
            let left = Duration.seconds(secondsLeft).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
            parts.append(String(localized: "\(left) left", table: "NotchcastDownloads"))
        }
        return parts.joined(separator: " · ")
    }

    static func short(_ name: String) -> String { name.count > 40 ? String(name.prefix(39)) + "…" : name }

    static func failure(_ job: TorrentJob) -> String {
        guard case .failed(let reason) = job.state else { return short(job.name) }
        return "\(short(job.name)): \(reason)"
    }
}
