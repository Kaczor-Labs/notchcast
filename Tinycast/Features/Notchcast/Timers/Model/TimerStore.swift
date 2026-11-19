import Foundation

/// One running timer as stored: an absolute end, so a relaunch carries on where it left off.
struct TimerEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var end: Date
    var label: String
    var isAlarm: Bool

    /// Still running, soonest first, and the ones whose end has come.
    static func split(_ timers: [TimerEntry], at now: Date) -> (running: [TimerEntry], ended: [TimerEntry]) {
        let sorted = timers.sorted { $0.end < $1.end }
        return (sorted.filter { $0.end > now }, sorted.filter { $0.end <= now })
    }
}

/// The running timers in the add-on's defaults; a timer leaves the moment it ends.
struct TimerStore {
    static let key = "timers.running"
    let defaults: UserDefaults

    /// Unreadable data counts as none: losing a countdown beats failing every launch.
    func load() -> [TimerEntry] {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([TimerEntry].self, from: $0) } ?? []
    }

    func save(_ timers: [TimerEntry]) {
        if timers.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Ended while nothing ran: removed here, so each is reported once.
    func resume(at now: Date) -> (running: [TimerEntry], missed: [TimerEntry]) {
        let (running, ended) = TimerEntry.split(load(), at: now)
        if !ended.isEmpty { save(running) }
        return (running, ended)
    }
}
