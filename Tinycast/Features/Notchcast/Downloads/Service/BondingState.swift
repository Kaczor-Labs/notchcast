import Foundation

/// Remembers which runs started on Wi-Fi and the iPhone, and whether that pair is still up.
@MainActor
final class BondingState {
    private let interfaces: @MainActor () -> [BondingInterface]
    private let now: @MainActor () -> Date
    private var torrents: BondedPair?
    private var downloads: [String: BondedPair] = [:]
    private var seen: (at: Date, interfaces: [BondingInterface])?

    init(interfaces: @escaping @MainActor () -> [BondingInterface], now: @escaping @MainActor () -> Date) {
        self.interfaces = interfaces
        self.now = now
    }

    /// True when both interfaces are up right now, so a download's size is worth asking for.
    var isPossible: Bool { BondingPolicy.pair(in: interfaces()) != nil }

    /// aria2c's extra flags for a torrent session starting now; every torrent shares that session.
    func startTorrents(enabled: Bool) -> [String] {
        torrents = BondingPolicy.pair(for: .torrent, enabled: enabled, interfaces: interfaces())
        return torrents?.arguments ?? []
    }

    /// aria2c's extra flags for one plain download; a nil size or a small file clears its mark.
    func startDownload(_ id: String, bytes: Int64?, enabled: Bool) -> [String] {
        downloads[id] = BondingPolicy.pair(for: .download(bytes: bytes), enabled: enabled, interfaces: interfaces())
        return downloads[id]?.arguments ?? []
    }

    var torrentsBonded: Bool { torrents.map(isLive) ?? false }

    /// True while a running job of this queue is still on both interfaces; finished jobs are forgotten.
    func downloadsBonded(_ jobs: [DownloadJob]) -> Bool {
        let running = Set(jobs.filter { $0.state == .running }.map(\.id))
        downloads = downloads.filter { running.contains($0.key) }
        return downloads.values.contains(where: isLive)
    }

    /// The island redraws on every progress line, so one look at the interfaces serves a whole second.
    private func isLive(_ pair: BondedPair) -> Bool {
        let time = now()
        if let seen, abs(time.timeIntervalSince(seen.at)) < 1 { return BondingPolicy.isLive(pair, in: seen.interfaces) }
        let fresh = interfaces()
        seen = (time, fresh)
        return BondingPolicy.isLive(pair, in: fresh)
    }
}
