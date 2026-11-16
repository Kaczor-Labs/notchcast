import Foundation

/// Notices stack newest on top; only the top's dwell runs, and only while it is seen.
struct IslandNoticeQueue: Sendable {
    private struct Entry: Sendable {
        var notice: IslandNotice
        var left: TimeInterval?
        var heard: Set<String> = []
    }

    private var entries: [Entry] = []
    private var since: TimeInterval?
    private(set) var paused = false

    var notice: IslandNotice? { entries.last?.notice }

    /// A repost keeps its place and restarts its dwell; a progress headlines once until ended.
    mutating func post(_ notice: IslandNotice, at now: TimeInterval) {
        settle(at: now)
        var notice = notice
        let index = entries.firstIndex { $0.notice.id == notice.id }
        let left: TimeInterval?
        if notice.progress == nil {
            left = notice.dwell
        } else if let index, let shown = entries[index].notice.progress {
            let headline = shown.headline && notice.isHeadline
            notice.progress?.headline = headline
            left = headline ? entries[index].left : nil
        } else {
            left = notice.isHeadline ? IslandNotice.messageSeconds : nil
        }
        if let index {
            entries[index] = Entry(notice: notice, left: left, heard: entries[index].heard)
        } else {
            entries.append(Entry(notice: notice, left: left))
        }
        run(at: now)
    }

    mutating func end(_ id: String, at now: TimeInterval) {
        settle(at: now)
        entries.removeAll { $0.notice.id == id }
        run(at: now)
    }

    mutating func pause(_ paused: Bool, at now: TimeInterval) {
        settle(at: now)
        self.paused = paused
        run(at: now)
    }

    /// The top's dwell still to run, or nil while it is paused, untimed or gone.
    func remaining(at now: TimeInterval) -> TimeInterval? {
        guard let since, let left = entries.last?.left else { return nil }
        return max(left - (now - since), 0)
    }

    /// The notice under an expired top returns with the dwell it had left.
    mutating func expire(at now: TimeInterval) {
        guard remaining(at: now) == 0, let top = entries.indices.last else { return }
        if entries[top].notice.progress == nil {
            entries.removeLast()
        } else {
            entries[top].notice.progress?.headline = false
            entries[top].left = nil
        }
        since = nil
        run(at: now)
    }

    /// Each text of an id is heard once, so a returning notice or a phase coming back stays quiet.
    mutating func announcement() -> String? {
        guard let top = entries.indices.last else { return nil }
        return entries[top].heard.insert(entries[top].notice.text).inserted ? entries[top].notice.text : nil
    }

    private mutating func settle(at now: TimeInterval) {
        if let since, let top = entries.indices.last, let left = entries[top].left {
            entries[top].left = max(left - (now - since), 0)
        }
        since = nil
    }

    private mutating func run(at now: TimeInterval) {
        since = !paused && entries.last?.left != nil ? now : nil
    }
}
