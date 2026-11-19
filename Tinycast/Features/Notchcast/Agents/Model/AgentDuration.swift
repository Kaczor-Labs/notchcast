import Foundation

enum AgentDuration {
    /// Two units at most, rounded down, never under a minute: "2 d 5 h", "3 h 20 min", "45 min".
    static func text(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.down)))
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

    static func until(_ date: Date, now: Date) -> String {
        String(localized: "in \(text(date.timeIntervalSince(now)))", table: "NotchcastAgents")
    }
}
