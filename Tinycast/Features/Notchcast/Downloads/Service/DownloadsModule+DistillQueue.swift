import Foundation

extension DownloadsModule {
    nonisolated enum DistillAction: Codable, Sendable {
        case remove(String), retry(String), run
        /// Settings sends the ids it showed; only those still failed here are touched.
        case removeFailed([String]), retryFailed([String])
    }

    var distillRows: [DistillQueueList.Row]? {
        guard context.isEnabled(Self.distillSwitchID), let queue = distill.queue else { return nil }
        return DistillQueueList.rows(queue.jobs)
    }

    func perform(_ action: DistillAction) {
        guard running, context.isEnabled(Self.distillSwitchID), let queue = distill.queue else { return }
        switch action {
        case .run:
            perform(.runDistill)
        case .remove(let id):
            guard queue.jobs.contains(where: { $0.id == id && !$0.source.hasPrefix("/") }) else { return }
            queue.remove([id])
        case .retry(let id):
            retry([id], in: queue) { $0.state.isFinished && $0.state != .done }
        case .removeFailed(let ids):
            let ids = Set(ids)
            let failed = queue.jobs.filter { ids.contains($0.id) && !$0.source.hasPrefix("/") && $0.state == .failed }
            if !failed.isEmpty { queue.remove(failed.map(\.id)) }
        case .retryFailed(let ids):
            retry(ids, in: queue) { $0.state == .failed }
        }
    }

    /// In queue order; a link already queued again, or named twice, is removed rather than run twice.
    private func retry(_ ids: [String], in queue: DownloadQueue, allowing allowed: (DownloadJob) -> Bool) {
        let ids = Set(ids)
        var queued = Set(queue.jobs.filter { !$0.state.isFinished }.map(\.source))
        var rerun: [String] = []
        var drop: [String] = []
        for job in queue.jobs where ids.contains(job.id) && !job.source.hasPrefix("/") && allowed(job) {
            if queued.insert(job.source).inserted { rerun.append(job.id) } else { drop.append(job.id) }
        }
        if !rerun.isEmpty || !drop.isEmpty { queue.retry(rerun, removing: drop) }
    }
}
