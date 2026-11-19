import Foundation

/// Every word the timers put on the island, in the user's locale and clock.
enum TimersText {
    static func symbol(_ timer: TimerEntry) -> String { timer.isAlarm ? "alarm" : "timer" }

    static func name(_ timer: TimerEntry) -> String {
        if !timer.label.isEmpty { return timer.label }
        return timer.isAlarm
            ? String(localized: "Alarm", table: "NotchcastTimers")
            : String(localized: "Timer", table: "NotchcastTimers")
    }

    static func started(_ timer: TimerEntry, now: Date) -> String {
        if timer.isAlarm { return String(localized: "Alarm set for \(clock(timer.end))", table: "NotchcastTimers") }
        let length = duration(timer.end.timeIntervalSince(now), units: [.hours, .minutes, .seconds])
        return String(localized: "Timer set for \(length)", table: "NotchcastTimers")
    }

    static func ringing(_ timer: TimerEntry) -> String {
        if !timer.label.isEmpty { return timer.label }
        return timer.isAlarm
            ? String(localized: "Alarm, \(clock(timer.end))", table: "NotchcastTimers")
            : String(localized: "Timer done", table: "NotchcastTimers")
    }

    static func missed(_ timer: TimerEntry) -> String {
        String(localized: "\(name(timer)) ended at \(clock(timer.end))", table: "NotchcastTimers")
    }

    static func stopped(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No timer running", table: "NotchcastTimers")
        case 1: String(localized: "Timer stopped", table: "NotchcastTimers")
        default: String(localized: "\(count) timers stopped", table: "NotchcastTimers")
        }
    }

    static func stopRow(_ timer: TimerEntry) -> String {
        String(localized: "Stop \(name(timer)) (\(clock(timer.end)))", table: "NotchcastTimers")
    }

    static func dismissRow(_ timer: TimerEntry) -> String {
        String(localized: "Dismiss \(name(timer))", table: "NotchcastTimers")
    }

    static func spoken(_ timer: TimerEntry, remaining: TimeInterval) -> String {
        let left = duration(remaining, units: remaining < 600 ? [.minutes, .seconds] : [.hours, .minutes])
        return String(localized: "\(name(timer)), \(left) left", table: "NotchcastTimers")
    }

    private static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    private static func duration(_ seconds: TimeInterval, units: Set<Duration.UnitsFormatStyle.Unit>) -> String {
        Duration.seconds(max(seconds, 0).rounded(.up)).formatted(.units(allowed: units, width: .abbreviated))
    }
}
