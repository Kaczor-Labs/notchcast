import Foundation

/// The last good document as of `now`: what waits, what is put off, and how far to trust it.
struct ThreadsBoard: Sendable {
    /// Older than this, the document or a machine counts as silent (design sheet r1, choice 3).
    static let silentAfter: TimeInterval = 5 * 60

    /// False until the first read ends: the add-on then shows nothing at all.
    var configured: Bool
    var document: ThreadsDocument?
    var now: Date
    /// The latest read failed: the last good rows stay, but never as current.
    var readFailed = false

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
    var notReporting: Bool { configured && (readFailed || (documentAge.map { $0 > Self.silentAfter } ?? true)) }

    /// When a document that is fresh now turns silent with no new read.
    var freshUntil: Date? { notReporting ? nil : document.map { $0.generatedAt.addingTimeInterval(Self.silentAfter) } }

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
    private(set) var ids: [String]

    init(ids: [String] = []) { self.ids = ids }

    /// The waits not announced before, now counted as announced; an id leaves only once its wait has.
    mutating func take(_ waits: [ThreadsDocument.Wait], present: [ThreadsDocument.Wait]) -> [ThreadsDocument.Wait] {
        let inFile = Set(present.compactMap(\.id))
        var known = Set(ids)
        let fresh = waits.filter { wait in wait.id.map { known.insert($0).inserted } ?? false }
        ids = ids.filter(inFile.contains) + fresh.compactMap(\.id)
        return fresh
    }
}

/// T3's own link to one thread, the only kind the add-on opens.
enum ThreadsLink {
    static let scheme = "t3code"

    static func url(_ wait: ThreadsDocument.Wait) -> URL? {
        guard let environment = wait.environmentID, let thread = wait.threadID,
              isSafe(environment), isSafe(thread) else { return nil }
        return URL(string: "\(scheme)://threads/\(segment(environment))/\(segment(thread))")
    }

    static func isOpenable(_ url: URL) -> Bool { url.scheme == scheme }

    /// An id from the file goes into a URL path, so nothing that could leave its segment passes.
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && !id.hasPrefix(".") && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// A `prefix:` id stays one segment: the colon goes out as `%3A`.
    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: unreserved) ?? id
    }

    private static let unreservedText = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
    private static let unreserved = CharacterSet(charactersIn: unreservedText)
    private static let allowed = Set((unreservedText + ":").unicodeScalars)
}
