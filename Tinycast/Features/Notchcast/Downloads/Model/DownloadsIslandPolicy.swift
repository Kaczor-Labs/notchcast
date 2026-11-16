import Foundation

/// What the island shows for one queue; pure, so a harness drives it with job lists.
struct DownloadsIslandPolicy: Equatable, Sendable {
    struct Shown: Equatable, Sendable {
        let title: String?
        let done: Int
        let total: Int
        let progress: Double?
    }

    private var batch: Set<String> = []
    private var failed: Set<String>

    /// Failures already in the queue when it loads were reported by an earlier run.
    init(loaded jobs: [DownloadJob]) {
        failed = Set(jobs.filter { $0.state == .failed }.map(\.id))
    }

    mutating func update(_ jobs: [DownloadJob]) -> (shown: Shown?, failures: [DownloadJob]) {
        let failures = jobs.filter { $0.state == .failed && !failed.contains($0.id) }
        failed = Set(jobs.filter { $0.state == .failed }.map(\.id))
        let pending = jobs.filter(\.state.isDue).map(\.id)
        guard !pending.isEmpty else {
            batch = []
            return (nil, failures)
        }
        batch.formUnion(pending)
        let inBatch = jobs.filter { batch.contains($0.id) }
        let current = DownloadsActivity(jobs: jobs)
        return (Shown(title: current.currentTitle, done: inBatch.count { $0.state.isFinished },
                      total: inBatch.count, progress: current.fraction), failures)
    }

    static func message(for job: DownloadJob) -> String {
        let title = job.title.count > 40 ? String(job.title.prefix(39)) + "…" : job.title
        guard let detail = job.detail, !detail.isEmpty else { return title }
        return "\(title): \(detail)"
    }
}
