import Foundation

/// Which files dropped into the Markdown folder Distill turns into notes, and when to look again.
nonisolated enum DistillDrop {
    enum Kind: Equatable, Sendable { case pdf, html, media }

    /// Which file a job read: trashing needs the same file, unchanged, still at its path.
    struct Stamp: Codable, Equatable, Sendable {
        let file: UInt64
        let size: UInt64
        let modified: Date
    }

    /// `stamp` is nil for anything but a plain regular file with a known id, size and modification date.
    struct Entry: Equatable, Sendable {
        let path: String
        let stamp: Stamp?
    }

    /// A file's stamp and when it was first seen with it.
    struct Sighting: Equatable, Sendable {
        let stamp: Stamp
        let since: Date
    }

    struct Plan: Sendable {
        var ready: [Entry] = []
        var seen: [String: Sighting] = [:]
        var recheck: Date?
    }

    /// A file still being copied in keeps changing; one unchanged across looks this far apart is whole.
    static let settle: TimeInterval = 5

    static func kind(of name: String) -> Kind? {
        switch URL(filePath: name).pathExtension.lowercased() {
        case "pdf": .pdf
        case "html", "htm": .html
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "mp4", "mov", "m4v", "webm", "mkv": .media
        default: nil
        }
    }

    /// Files ready to convert in name order, what is still settling, and when to look again.
    /// Markdown, hidden or partial files, symlinks and files already queued are skipped; a failed one
    /// is retried only when `retryFailed`, so a broken file does not fail again on every change.
    static func plan(
        _ entries: [Entry], jobs: [DownloadJob], seen: [String: Sighting], now: Date, retryFailed: Bool
    ) -> Plan {
        let taken = Set(jobs.filter { !$0.state.isFinished || (!retryFailed && $0.state == .failed) }.map(\.source))
        var plan = Plan()
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let name = URL(filePath: entry.path).lastPathComponent
            guard !name.hasPrefix("."), let stamp = entry.stamp, kind(of: name) != nil else { continue }
            let since = seen[entry.path].flatMap { $0.stamp == stamp ? $0.since : nil } ?? now
            let ready = since.addingTimeInterval(settle)
            let isTaken = taken.contains(entry.path)
            if !isTaken && ready <= now {
                plan.ready.append(entry)
                continue
            }
            // A taken file is remembered too, so Run Distill retries a long-settled failed one at once.
            plan.seen[entry.path] = Sighting(stamp: stamp, since: since)
            if !isTaken { plan.recheck = min(plan.recheck ?? ready, ready) }
        }
        return plan
    }

    /// True only for a file directly inside `folder`, compared after standardizing both paths.
    static func isDirectlyInside(_ path: String, _ folder: URL) -> Bool {
        let parent = URL(filePath: path).standardizedFileURL.deletingLastPathComponent()
        return parent.standardizedFileURL.pathComponents == folder.standardizedFileURL.pathComponents
    }

    /// Unfinished dropped-file jobs that no longer belong to the watched folder: all of them once it is nil.
    static func orphans(_ jobs: [DownloadJob], kind: String, folder: URL?) -> [String] {
        jobs.filter { job in
            job.kind == kind && !job.state.isFinished && job.source.hasPrefix("/")
                && !(folder.map { isDirectlyInside(job.source, $0) } ?? false)
        }.map(\.id)
    }
}
