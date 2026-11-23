import Foundation

/// The last good document as of `now`: what waits, what is put off, and how far to trust it.
struct ThreadsBoard: Sendable {
    /// Older than this, the document or a machine counts as silent (design sheet r1, choice 3).
    static let silentAfter: TimeInterval = 5 * 60

    /// False while Settings names no waits file: the add-on then shows nothing at all.
    var configured: Bool
    var document: ThreadsDocument?
    var now: Date

    /// Waiting on the user, newest first.
    var waiting: [ThreadsDocument.Wait] {
        (document?.waits ?? []).filter { !$0.later }.sorted { age(of: $0) < age(of: $1) }
    }

    var later: [ThreadsDocument.Wait] {
        (document?.waits ?? []).filter(\.later).sorted { age(of: $0) < age(of: $1) }
    }

    var failedCount: Int { waiting.count { $0.kind == .failedRun } }

    /// Nil with no document; else how long since t3chad last wrote it.
    var documentAge: TimeInterval? { document.map { max(0, now.timeIntervalSince($0.generatedAt)) } }

    /// Silence never passes for "nothing waits": no readable document, or one t3chad stopped rewriting.
    var notReporting: Bool { configured && (documentAge.map { $0 > Self.silentAfter } ?? true) }

    /// Machines whose own reading is old in a document that is itself fresh; nil age is one never read.
    var silentMachines: [(machine: String, age: TimeInterval?)] {
        guard let document, !notReporting, let documentAge else { return [] }
        return document.sources.compactMap { source in
            let age = source.ageSeconds.map { TimeInterval($0) + documentAge }
            guard source.readAt == nil || source.stale || (age ?? .infinity) > Self.silentAfter else { return nil }
            return (source.machine, source.readAt == nil ? nil : age)
        }
    }

    /// Waits a fresh document lets the island announce: never one put off, never one from a silent document.
    var announceable: [ThreadsDocument.Wait] { notReporting ? [] : waiting.filter { $0.id != nil } }

    func age(of wait: ThreadsDocument.Wait) -> TimeInterval {
        if let since = wait.since { return max(0, now.timeIntervalSince(since)) }
        return TimeInterval(wait.waitingSeconds) + (documentAge ?? 0)
    }

    static func title(_ wait: ThreadsDocument.Wait) -> String {
        if let title = wait.title { return title }
        return wait.kind == .doorAsk
            ? String(localized: "Door", table: "NotchcastThreads")
            : String(localized: "Thread", table: "NotchcastThreads")
    }

    /// "2 min", "3 h": how long something has waited, at the list's grain.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "now", table: "NotchcastThreads") }
        if minutes < 60 { return String(localized: "\(minutes) min", table: "NotchcastThreads") }
        if minutes < 24 * 60 { return String(localized: "\(minutes / 60) h", table: "NotchcastThreads") }
        return String(localized: "\(minutes / (24 * 60)) d", table: "NotchcastThreads")
    }
}

/// The wait ids already announced, kept across restarts so a wait is announced once.
struct ThreadsShown: Equatable, Sendable {
    /// Far above the waits one user keeps; the oldest ids go first.
    static let cap = 500

    private(set) var ids: [String]

    init(ids: [String] = []) { self.ids = Array(ids.suffix(Self.cap)) }

    /// The waits not announced before, now counted as announced.
    mutating func take(_ waits: [ThreadsDocument.Wait]) -> [ThreadsDocument.Wait] {
        var known = Set(ids)
        let fresh = waits.filter { wait in wait.id.map { known.insert($0).inserted } ?? false }
        ids = Array((ids + fresh.compactMap(\.id)).suffix(Self.cap))
        return fresh
    }
}

/// T3's own link to one thread, the only kind the add-on opens.
enum ThreadsLink {
    static let scheme = "t3code"

    static func url(_ wait: ThreadsDocument.Wait) -> URL? {
        guard let environment = wait.environmentID, let thread = wait.threadID,
              isSafe(environment), isSafe(thread) else { return nil }
        return URL(string: "\(scheme)://threads/\(environment)/\(thread)")
    }

    static func isOpenable(_ url: URL) -> Bool { url.scheme == scheme }

    /// An id from the file goes into a URL path, so nothing that could leave its segment passes.
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && !id.hasPrefix(".") && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".unicodeScalars)
}
