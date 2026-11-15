import Foundation

/// In memory only, so a relaunch expands the carded meeting once more.
struct IslandMeetingExpansion: Equatable, Sendable {
    struct Occurrence: Hashable, Sendable {
        let id: String
        let start: Date
    }

    let seconds: TimeInterval
    private(set) var spent: Set<Occurrence> = []
    private(set) var showing: Occurrence?
    /// A stale settle task never clears a newer expansion.
    private(set) var presentation = 0
    private var deadline: TimeInterval = 0

    init(seconds: TimeInterval = 6) { self.seconds = seconds }

    /// A level makes it wait; a cover at window start or a level cutting in spends it.
    mutating func update(carded: Occurrence?, waiting: Bool, covered: Bool, at now: TimeInterval) -> Bool {
        spent = spent.filter { $0 == carded }
        if let showing, showing != carded || waiting || covered || now >= deadline { self.showing = nil }
        guard let carded, showing == nil, !spent.contains(carded) else { return false }
        if covered { spent.insert(carded) }
        guard !covered, !waiting else { return false }
        spent.insert(carded)
        showing = carded
        deadline = now + seconds
        presentation += 1
        return true
    }

    /// Expiry clears the expansion here, so the settle task is the only clock.
    mutating func remaining(_ token: Int, at now: TimeInterval) -> TimeInterval? {
        guard token == presentation, showing != nil else { return nil }
        guard now < deadline else { showing = nil; return nil }
        return deadline - now
    }
}
