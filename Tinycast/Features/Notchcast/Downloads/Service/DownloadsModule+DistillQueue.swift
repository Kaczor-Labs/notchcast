import Foundation

extension DownloadsModule {
    nonisolated enum DistillAction: Codable, Sendable {
        case remove(String), retry(String), run
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
            queue.remove(id)
        case .retry(let id):
            guard let job = queue.jobs.first(where: { $0.id == id && !$0.source.hasPrefix("/") }),
                  job.state.isFinished, job.state != .done else { return }
            if queue.jobs.contains(where: { $0.source == job.source && !$0.state.isFinished }) {
                queue.remove(id)
            } else {
                queue.retry(id)
            }
        }
    }
}
