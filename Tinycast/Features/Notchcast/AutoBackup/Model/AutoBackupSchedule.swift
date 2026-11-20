import Foundation

/// When the settings get backed up, and which of this Mac's own backups rotate out.
struct AutoBackupSchedule: Codable, Equatable, Sendable {
    static let debounce: TimeInterval = 30
    static let minimumGap: TimeInterval = 10 * 60
    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let defaultKeep = 10
    static let keepRange = 1...50
    static let folderName = "Notchcast Backups"
    static let fileExtension = "tinycast"
    /// The first backup waits this long after switching on, so a folder can be chosen first.
    static let firstDelay: TimeInterval = minimumGap

    /// Paths this Mac wrote, oldest first: rotation deletes nothing else.
    var written: [String] = []
    var lastDigest: String?
    var lastWrite: Date?
    var lastCheck: Date?
    var pendingChange: Date?
    var isFailing = false
    var firstDue: Date?

    enum Action: Equatable, Sendable {
        case skip
        case write(name: String)
    }

    mutating func noteChange(at now: Date) { pendingChange = now }

    mutating func noteStart(at now: Date) {
        guard lastWrite == nil, (firstDue ?? .distantPast) <= now else { return }
        firstDue = now.addingTimeInterval(Self.firstDelay)
    }

    /// A change waits out the debounce and the gap since the last write; without one, a daily check.
    func due() -> Date {
        let daily = (lastCheck ?? .distantPast).addingTimeInterval(Self.checkInterval)
        let next = pendingChange.map { change in
            min(max(change.addingTimeInterval(Self.debounce),
                    (lastWrite ?? .distantPast).addingTimeInterval(Self.minimumGap)), daily)
        } ?? daily
        guard lastWrite == nil, let firstDue else { return next }
        return max(next, firstDue)
    }

    /// nil before `due()`; skips when the settings match the last backup and that file is still there.
    mutating func tick(at now: Date, digest: String, timeZone: TimeZone, exists: (String) -> Bool) -> Action? {
        guard now >= due() else { return nil }
        lastCheck = now
        pendingChange = nil
        if digest == lastDigest, let latest = written.last, exists(latest) { return .skip }
        return .write(name: Self.fileName(at: now, timeZone: timeZone))
    }

    /// Records a finished write; returns the paths that rotate out, oldest first.
    mutating func didWrite(_ path: String, digest: String, at now: Date, keep: Int, exists: (String) -> Bool)
        -> [String]
    {
        lastWrite = now
        lastDigest = digest
        isFailing = false
        written = written.filter { $0 != path && exists($0) } + [path]
        let limit = min(max(keep, Self.keepRange.lowerBound), Self.keepRange.upperBound)
        let removed = Array(written.prefix(max(0, written.count - limit)))
        written.removeFirst(removed.count)
        return removed
    }

    /// True only for the first failure in a row, so one notice reports it until a write succeeds.
    mutating func didFail() -> Bool {
        defer { isFailing = true }
        return !isFailing
    }

    /// Sorts by time, and never matches the stock export's `Notchcast-<date>` name.
    static func fileName(at date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d %02d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
            c.minute ?? 0, c.second ?? 0)
        return "Notchcast Settings \(stamp).\(fileExtension)"
    }

    /// The chosen folder or `~/Documents/Notchcast Backups`, plus a subfolder per non-release channel.
    static func folder(chosen: String?, documents: URL, channel: String?) -> URL {
        let base = chosen.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? documents.appending(path: folderName, directoryHint: .isDirectory)
        return channel.map { base.appending(path: $0, directoryHint: .isDirectory) } ?? base
    }
}
