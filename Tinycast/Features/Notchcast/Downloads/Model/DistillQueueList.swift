import Foundation

nonisolated enum DistillQueueList {
    struct Row: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let state: DownloadState
        var note: String
        /// Why a failed or held link stopped, with yt-dlp's per-video prefix cut.
        var reason: String?

        var canRetry: Bool { state.isFinished && state != .done }
        var needsDictationModel: Bool { reason.map(DistillQueueList.needsDictationModel) ?? false }
    }

    struct SharedFailure: Equatable {
        let reason: String
        let count: Int
        let failed: Int

        var needsDictationModel: Bool { DistillQueueList.needsDictationModel(reason) }
    }

    /// Unfinished links in queue order, then failed, cancelled and interrupted, then saved, newest first.
    static func rows(_ jobs: [DownloadJob]) -> [Row] {
        let links = jobs.filter { !$0.source.hasPrefix("/") }
        let saved = Set(links.filter { $0.state == .done }.map(\.source))
        let shown = links.enumerated()
            .filter { !($0.element.state == .failed && saved.contains($0.element.source)) }
            .sorted { lhs, rhs in
                let left = rank(lhs.element), right = rank(rhs.element)
                if left != right { return left < right }
                if left == 0 { return lhs.offset < rhs.offset }
                let leftTime = lhs.element.finished ?? lhs.element.created
                let rightTime = rhs.element.finished ?? rhs.element.created
                return leftTime != rightTime ? leftTime > rightTime : lhs.offset < rhs.offset
            }
            .map { Row(id: $0.element.id, name: name($0.element.source), state: $0.element.state,
                       note: note($0.element), reason: reason($0.element)) }
        guard let common = sharedFailure(shown) else { return shown }
        return shown.map { row in
            var row = row
            if row.state == .failed, row.reason == common.reason {
                row.note = String(localized: "Failed", table: "NotchcastDownloads")
            }
            return row
        }
    }

    /// The most common reason among failed rows, when at least two share it.
    static func sharedFailure(_ rows: [Row]) -> SharedFailure? {
        let reasons = rows.filter { $0.state == .failed }.compactMap(\.reason)
        let counts = reasons.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        guard let count = counts.values.max(), count >= 2,
              let best = reasons.first(where: { counts[$0] == count }) else { return nil }
        return SharedFailure(reason: best, count: count, failed: rows.count { $0.state == .failed })
    }

    static func failedLine(_ rows: [Row]) -> String {
        String(localized: "\(rows.count { $0.state == .failed }) failed links", table: "NotchcastDownloads")
    }

    static func sharedLine(_ shared: SharedFailure) -> String {
        if shared.needsDictationModel {
            return String(localized: "\(shared.count) need a dictation model", table: "NotchcastDownloads")
        }
        return String(localized: "\(shared.count) of \(shared.failed): \(shared.reason)", table: "NotchcastDownloads")
    }

    /// English only, so the speech model's own failure texts name the cause.
    static func needsDictationModel(_ reason: String) -> Bool {
        ["Parakeet Ultra could not be prepared.", "Download the selected dictation model first."]
            .contains { reason.hasPrefix($0) }
    }

    private static func rank(_ job: DownloadJob) -> Int {
        job.state == .done ? 2 : job.state.isFinished ? 1 : 0
    }

    private static func reason(_ job: DownloadJob) -> String? {
        guard job.state == .failed || job.state == .held, let detail = job.detail, !detail.isEmpty else { return nil }
        return String(detail.trimmingPrefix(#/ERROR: \[[^\]]+\] [^:\s]+: /#))
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
        case .held:
            if let detail = job.detail, !detail.isEmpty {
                detail
            } else {
                String(localized: "Held until Run Distill", table: "NotchcastDownloads")
            }
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
