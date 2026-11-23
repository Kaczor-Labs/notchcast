import Foundation

nonisolated enum DistillQueueList {
    struct Row: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let state: DownloadState
        let note: String

        var canRetry: Bool { state.isFinished && state != .done }
    }

    static func rows(_ jobs: [DownloadJob]) -> [Row] {
        let links = jobs.filter { !$0.source.hasPrefix("/") }
        let unfinished = links.filter { !$0.state.isFinished }
        let finished = links.filter { $0.state.isFinished }.sorted {
            ($0.finished ?? $0.created) > ($1.finished ?? $1.created)
        }
        return (unfinished + finished).map { job in
            Row(id: job.id, name: name(job.source), state: job.state, note: note(job))
        }
    }

    static func countLine(_ rows: [Row]) -> String {
        let queued = rows.count { !$0.state.isFinished }
        let failed = rows.count { $0.state == .failed }
        if failed > 0 {
            return String(localized: "\(queued) links queued · \(failed) failed", table: "NotchcastDownloads")
        }
        return String(localized: "\(queued) links queued", table: "NotchcastDownloads")
    }

    private static func name(_ source: String) -> String {
        let lowercase = source.lowercased()
        guard let scheme = ["https://", "http://"].first(where: { lowercase.hasPrefix($0) }) else { return source }
        let address = source.dropFirst(scheme.count)
        return address.lowercased().hasPrefix("www.") ? String(address.dropFirst("www.".count)) : String(address)
    }

    private static func note(_ job: DownloadJob) -> String {
        switch job.state {
        case .held: String(localized: "Held until Run Distill", table: "NotchcastDownloads")
        case .waiting: String(localized: "Waiting", table: "NotchcastDownloads")
        case .running: job.progress?.stage ?? String(localized: "Running", table: "NotchcastDownloads")
        case .done:
            if let output = job.output {
                String(localized: "Saved \(URL(filePath: output).lastPathComponent)", table: "NotchcastDownloads")
            } else {
                String(localized: "Saved", table: "NotchcastDownloads")
            }
        case .failed:
            if let detail = job.detail, !detail.isEmpty {
                String(localized: "Failed: \(detail)", table: "NotchcastDownloads")
            } else {
                String(localized: "Failed", table: "NotchcastDownloads")
            }
        case .cancelled: String(localized: "Cancelled", table: "NotchcastDownloads")
        case .interrupted: String(localized: "Interrupted", table: "NotchcastDownloads")
        }
    }
}
