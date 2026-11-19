import Foundation

/// The pill's countdown in at most four characters, and how long until that text changes.
enum TimerClock {
    /// `9:59` under ten minutes, then `25m`, `1h05` and `12h`; seconds round up, so `0:01` is last.
    static func text(remaining: TimeInterval) -> String {
        let seconds = wholeSeconds(remaining)
        if seconds < 600 { return "\(seconds / 60):" + twoDigits(seconds % 60) }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 600 { return "\(minutes / 60)h" + twoDigits(minutes % 60) }
        return "\((minutes + 59) / 60)h"
    }

    /// Zero once it has run out; never later than the next change of `text`.
    static func untilChange(remaining: TimeInterval) -> TimeInterval {
        let seconds = wholeSeconds(remaining)
        guard seconds > 0 else { return 0 }
        let minutes = (seconds + 59) / 60
        let next = if seconds < 600 {
            seconds - 1
        } else if minutes < 600 {
            max((minutes - 1) * 60, 599)
        } else {
            max(((minutes + 59) / 60 - 1) * 3600, 599 * 60)
        }
        return max(min(remaining, TimeInterval(maximumSeconds)) - TimeInterval(next), 0)
    }

    /// Stored dates are outside data, so a far-off end is capped before it becomes an `Int`.
    private static let maximumSeconds = 99 * 3600

    private static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        guard remaining.isFinite else { return remaining > 0 ? maximumSeconds : 0 }
        return Int(min(max(remaining, 0), TimeInterval(maximumSeconds)).rounded(.up))
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
