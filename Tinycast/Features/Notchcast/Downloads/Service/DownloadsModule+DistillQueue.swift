import Foundation

extension DownloadsModule {
    nonisolated enum DistillAction: Codable, Sendable {
        case remove([String]), retry([String]), run
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
        case .remove(let ids):
            let ids = Set(ids)
            queue.remove(queue.jobs.filter { ids.contains($0.id) && !$0.source.hasPrefix("/") }.map(\.id))
        case .retry(let ids):
            let ids = Set(ids)
            // A link already queued again, or named twice, is removed rather than run twice.
            var queued = Set(queue.jobs.filter { !$0.state.isFinished }.map(\.source))
            var rerun: [String] = []
            var drop: [String] = []
            for job in queue.jobs where ids.contains(job.id) && !job.source.hasPrefix("/")
                && job.state.isFinished && job.state != .done {
                if queued.insert(job.source).inserted { rerun.append(job.id) } else { drop.append(job.id) }
            }
            if !drop.isEmpty { queue.remove(drop) }
            if !rerun.isEmpty { queue.retry(rerun) }
        }
    }
}
