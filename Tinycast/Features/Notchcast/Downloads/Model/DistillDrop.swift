import Foundation

/// Which files dropped into the Markdown folder Distill turns into notes, and when to look again.
nonisolated enum DistillDrop {
    enum Kind: Equatable, Sendable { case pdf, html, media }

    struct Entry: Equatable, Sendable {
        let path: String
        let isRegularFile: Bool
        let isSymbolicLink: Bool
        let modified: Date
    }

    /// A file still being copied in keeps changing; one untouched this long is taken as whole.
    static let settle: TimeInterval = 5

    static func kind(of name: String) -> Kind? {
        switch URL(filePath: name).pathExtension.lowercased() {
        case "pdf": .pdf
        case "html", "htm": .html
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "mp4", "mov", "m4v", "webm", "mkv": .media
        default: nil
        }
    }

    /// Files ready to convert in name order, and when the soonest one still settling is ready.
    /// Markdown, hidden or partial files, symlinks and files already queued are skipped; a failed one
    /// is retried only when `retryFailed`, so a broken file does not fail again on every change.
    static func plan(
        _ entries: [Entry], jobs: [DownloadJob], now: Date, retryFailed: Bool
    ) -> (sources: [String], recheck: Date?) {
        let taken = Set(jobs.filter { !$0.state.isFinished || (!retryFailed && $0.state == .failed) }.map(\.source))
        var sources: [String] = []
        var recheck: Date?
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let name = URL(filePath: entry.path).lastPathComponent
            guard !name.hasPrefix("."), entry.isRegularFile, !entry.isSymbolicLink, kind(of: name) != nil,
                  !taken.contains(entry.path) else { continue }
            let ready = entry.modified.addingTimeInterval(settle)
            if ready > now {
                recheck = min(recheck ?? ready, ready)
            } else {
                sources.append(entry.path)
            }
        }
        return (sources, recheck)
    }
}
