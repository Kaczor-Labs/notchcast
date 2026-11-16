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

    mutating func update(_ jobs: [DownloadJob]) -> (shown: Shown?, failures: [DownloadJob], saved: [DownloadJob]) {
        let failures = jobs.filter { $0.state == .failed && !failed.contains($0.id) }
        failed = Set(jobs.filter { $0.state == .failed }.map(\.id))
        let pending = jobs.filter(\.state.isDue).map(\.id)
        guard !pending.isEmpty else {
            let saved = jobs.filter { batch.contains($0.id) && $0.state == .done }
            batch = []
            return (nil, failures, saved)
        }
        batch.formUnion(pending)
        let inBatch = jobs.filter { batch.contains($0.id) }
        let current = DownloadsActivity(jobs: jobs)
        return (Shown(title: current.currentTitle, done: inBatch.count { $0.state.isFinished },
                      total: inBatch.count, progress: current.fraction), failures, [])
    }

    /// "Saved page.html" for one job, "Saved 3 items" for a batch; the title when a job left no file.
    static func savedMessage(for jobs: [DownloadJob]) -> String {
        guard jobs.count == 1, let job = jobs.first else {
            return String(localized: "Saved \(jobs.count) items", table: "NotchcastDownloads")
        }
        let name = job.output.map { URL(filePath: $0).lastPathComponent } ?? job.title
        return String(localized: "Saved \(name.count > 40 ? String(name.prefix(39)) + "…" : name)",
                      table: "NotchcastDownloads")
    }

    static func message(for job: DownloadJob) -> String {
        let title = job.title.count > 40 ? String(job.title.prefix(39)) + "…" : job.title
        guard let detail = job.detail, !detail.isEmpty else { return title }
        return "\(title): \(detail)"
    }
}
