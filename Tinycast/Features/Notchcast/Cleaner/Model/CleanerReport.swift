import Foundation

struct CleanerReport: Sendable {
    enum Skip: Equatable, Sendable {
        case missing
        case changed
        case heldBack(CleanerHoldBack)
    }

    enum Outcome: Equatable, Sendable {
        case trashed(MeasuredSize?)
        case skipped(Skip)
        case failed
    }

    struct Entry: Equatable, Sendable {
        let id: URL
        let outcome: Outcome
    }

    var entries: [Entry] = []
    var cancelled = false

    var movedCount: Int {
        entries.count { if case .trashed = $0.outcome { true } else { false } }
    }

    var knownMovedBytes: Int64 {
        entries.reduce(0) { total, entry in
            guard case .trashed(let size) = entry.outcome else { return total }
            return total + (size?.bytes ?? 0)
        }
    }
}
