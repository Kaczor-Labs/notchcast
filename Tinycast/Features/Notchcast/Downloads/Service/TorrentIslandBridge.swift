import Foundation
import Observation

/// Mirrors the torrent jobs onto the island while the manager lives.
@MainActor
final class TorrentIslandBridge {
    static let progressID = "torrents.progress"
    private weak var manager: TorrentManager?
    private let presenter: any IslandPresenting
    private let reveal: @MainActor @Sendable ([URL]) -> Void
    private let bonded: @MainActor () -> Bool
    private var policy = TorrentIslandPolicy()
    private var showing = false

    private init(manager: TorrentManager, presenter: any IslandPresenting,
                 reveal: @escaping @MainActor @Sendable ([URL]) -> Void, bonded: @escaping @MainActor () -> Bool) {
        self.bonded = bonded
        self.manager = manager
        self.presenter = presenter
        self.reveal = reveal
    }

    static func track(_ manager: TorrentManager, presenter: any IslandPresenting,
                      reveal: @escaping @MainActor @Sendable ([URL]) -> Void,
                      bonded: @escaping @MainActor () -> Bool = { false }) {
        TorrentIslandBridge(manager: manager, presenter: presenter, reveal: reveal, bonded: bonded).observe()
    }

    /// The onChange closure owns the bridge, so it lives while there is something to observe.
    private func observe() {
        guard let manager else { return }
        let jobs = withObservationTracking { manager.jobs } onChange: { [self] in
            Task { @MainActor in observe() }
        }
        apply(policy.update(jobs))
    }

    private func apply(_ update: TorrentIslandPolicy.Update) {
        if let progress = update.progress {
            showing = true
            let marked = bonded()
            presenter.post(IslandNotice(id: Self.progressID, symbol: marked ? BondingPolicy.markSymbol : "arrow.down.circle",
                                        text: marked ? BondingPolicy.marked(progress.text) : progress.text,
                                        progress: IslandProgress(fraction: progress.fraction)), onTap: nil)
        } else if showing {
            showing = false
            presenter.end(notice: Self.progressID)
        }
        for job in update.failed {
            presenter.post(IslandNotice(id: "torrents.failed." + job.id.uuidString, symbol: "exclamationmark.triangle",
                                        text: TorrentIslandPolicy.failure(job), isFailure: true), onTap: nil)
        }
        for job in update.finished {
            let files = job.files
            let text = String(localized: "\(TorrentIslandPolicy.short(job.name)) finished. Show in Finder",
                              table: "NotchcastDownloads")
            let reveal = reveal
            var onTap: (@MainActor () -> Void)?
            if !files.isEmpty { onTap = { reveal(files) } }
            presenter.post(IslandNotice(id: "torrents.finished." + job.id.uuidString, symbol: "checkmark.circle",
                                        text: text), onTap: onTap)
        }
    }
}
