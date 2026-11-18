import Foundation
import Observation

/// Mirrors one queue onto the island through the add-on's presenter while its controller lives.
@MainActor
final class DownloadsIslandBridge {
    private weak var controller: DownloadsQueueController?
    private let presenter: any IslandPresenting
    private let noticeID: String
    private let symbol: String
    private let bonded: @MainActor ([DownloadJob]) -> Bool
    private var queue: ObjectIdentifier?
    private var policy: DownloadsIslandPolicy?
    private var showing = false

    private init(controller: DownloadsQueueController, presenter: any IslandPresenting, noticeID: String,
                 symbol: String, bonded: @escaping @MainActor ([DownloadJob]) -> Bool) {
        self.controller = controller
        self.presenter = presenter
        self.noticeID = noticeID
        self.symbol = symbol
        self.bonded = bonded
    }

    static func track(_ controller: DownloadsQueueController, presenter: any IslandPresenting,
                      noticeID: String, symbol: String,
                      bonded: @escaping @MainActor ([DownloadJob]) -> Bool = { _ in false }) {
        DownloadsIslandBridge(controller: controller, presenter: presenter, noticeID: noticeID, symbol: symbol,
                              bonded: bonded).observe()
    }

    /// The onChange closure owns the bridge, so it lives while there is something to observe.
    private func observe() {
        guard let controller else { return finish() }
        let (queue, jobs) = withObservationTracking {
            (controller.queue, controller.queue?.jobs ?? [])
        } onChange: { [self] in
            Task { @MainActor in observe() }
        }
        apply(queue.map(ObjectIdentifier.init), jobs: jobs)
    }

    private func apply(_ id: ObjectIdentifier?, jobs: [DownloadJob]) {
        guard let id else {
            queue = nil
            policy = nil
            return finish(result: IslandNotice(id: noticeID + ".stopped", symbol: "stop.circle",
                                               text: String(localized: "Stopped", table: "NotchcastDownloads")))
        }
        if queue != id {
            queue = id
            policy = DownloadsIslandPolicy(loaded: jobs)
        }
        guard let result = policy?.update(jobs) else { return }
        for job in result.failures {
            presenter.post(IslandNotice(id: noticeID + ".failed." + job.id, symbol: symbol,
                                        text: DownloadsIslandPolicy.message(for: job), isFailure: true), onTap: nil)
        }
        if !result.saved.isEmpty || !result.cancelled.isEmpty {
            showing = false
            presenter.end(notice: noticeID)
        }
        if !result.cancelled.isEmpty {
            presenter.post(IslandNotice(id: noticeID + ".cancelled", symbol: "xmark.circle",
                                        text: String(localized: "Cancelled", table: "NotchcastDownloads")), onTap: nil)
        }
        if !result.saved.isEmpty {
            presenter.post(IslandNotice(id: noticeID + ".saved", symbol: "checkmark.circle",
                                        text: DownloadsIslandPolicy.savedMessage(for: result.saved)), onTap: nil)
        }
        guard let shown = result.shown else { return finish() }
        let title = shown.title ?? String(localized: "Downloading", table: "NotchcastDownloads")
        let text = shown.total > 1
            ? String(localized: "\(shown.done + 1) of \(shown.total): \(title)", table: "NotchcastDownloads")
            : title
        showing = true
        let marked = bonded(jobs)
        presenter.post(IslandNotice(id: noticeID, symbol: marked ? BondingPolicy.markSymbol : symbol,
                                    text: marked ? BondingPolicy.marked(text) : text,
                                    progress: IslandProgress(fraction: shown.progress)), onTap: nil)
    }

    /// Ends the progress; a stopped queue leaves `result` behind, an emptied one nothing.
    private func finish(result: IslandNotice? = nil) {
        guard showing else { return }
        showing = false
        presenter.end(notice: noticeID)
        if let result { presenter.post(result, onTap: nil) }
    }
}
