import Foundation
import Observation

/// Mirrors one queue onto the island through the add-on's presenter while its controller lives.
@MainActor
final class DownloadsIslandBridge {
    private weak var controller: DownloadsQueueController?
    private let presenter: any IslandPresenting
    private let noticeID: String
    private let symbol: String
    private var queue: ObjectIdentifier?
    private var policy: DownloadsIslandPolicy?
    private var showing = false

    private init(controller: DownloadsQueueController, presenter: any IslandPresenting, noticeID: String,
                 symbol: String) {
        self.controller = controller
        self.presenter = presenter
        self.noticeID = noticeID
        self.symbol = symbol
    }

    static func track(_ controller: DownloadsQueueController, presenter: any IslandPresenting,
                      noticeID: String, symbol: String) {
        DownloadsIslandBridge(controller: controller, presenter: presenter, noticeID: noticeID, symbol: symbol)
            .observe()
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
            return finish()
        }
        if queue != id {
            queue = id
            policy = DownloadsIslandPolicy(loaded: jobs)
        }
        guard let result = policy?.update(jobs) else { return }
        for job in result.failures {
            presenter.post(IslandNotice(id: noticeID + ".failed." + job.id, symbol: symbol,
                                        text: DownloadsIslandPolicy.message(for: job), isFailure: true,
                                        seconds: 5), onTap: nil)
        }
        guard let shown = result.shown else { return finish() }
        let title = shown.title ?? String(localized: "Downloading", table: "NotchcastDownloads")
        let text = shown.total > 1
            ? String(localized: "\(shown.done + 1) of \(shown.total): \(title)", table: "NotchcastDownloads")
            : title
        showing = true
        // A notice without progress expires on its own, so an unknown fraction shows as zero.
        presenter.post(IslandNotice(id: noticeID, symbol: symbol, text: text, progress: shown.progress ?? 0),
                       onTap: nil)
    }

    private func finish() {
        guard showing else { return }
        showing = false
        presenter.end(notice: noticeID)
    }
}
