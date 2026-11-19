import Foundation

enum AgentDuration {
    /// Two units at most, rounded down, never under a minute: "2 d 5 h", "3 h 20 min", "45 min".
    static func text(_ seconds: TimeInterval) -> String {
        let minutes = Int(min(max(1, (seconds.isNaN ? 0 : seconds) / 60), 1e9).rounded(.down))
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        let rest = minutes % 60
        if days > 0 {
            return hours > 0
                ? String(localized: "\(days) d \(hours) h", table: "NotchcastAgents")
                : String(localized: "\(days) d", table: "NotchcastAgents")
        }
        if hours > 0 {
            return rest > 0
                ? String(localized: "\(hours) h \(rest) min", table: "NotchcastAgents")
                : String(localized: "\(hours) h", table: "NotchcastAgents")
        }
        return String(localized: "\(rest) min", table: "NotchcastAgents")
    }

    /// For VoiceOver: "5 days 14 hours", the same two units as `text`, in words.
    static func spoken(_ seconds: TimeInterval) -> String {
        let minutes = Int(min(max(60, seconds.isNaN ? 0 : seconds), 1e11) / 60)
        let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        let components = days > 0 ? DateComponents(day: days, hour: hours) : DateComponents(hour: hours, minute: rest)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        return formatter.string(from: components)?.replacingOccurrences(of: ",", with: "") ?? text(seconds)
    }

    static func until(_ date: Date, now: Date) -> String {
        String(localized: "in \(text(date.timeIntervalSince(now)))", table: "NotchcastAgents")
    }
}
