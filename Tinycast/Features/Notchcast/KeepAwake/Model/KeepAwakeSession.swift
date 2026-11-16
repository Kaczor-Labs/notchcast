import Foundation

struct KeepAwakeSession: Sendable, Equatable {
    enum Trigger: Sendable, Equatable { case manual, automation }

    var trigger: Trigger
    /// `nil` runs until turned off.
    var end: Date?
    var minutes: Int?

    static func manual(minutes: Int, now: Date) -> KeepAwakeSession {
        guard minutes > 0 else { return KeepAwakeSession(trigger: .manual) }
        return KeepAwakeSession(trigger: .manual, end: now.addingTimeInterval(Double(minutes * 60)), minutes: minutes)
    }

    static let automatic = KeepAwakeSession(trigger: .automation)

    var isAutomatic: Bool { trigger == .automation }

    /// Only a session the person started survives a relaunch; automation re-derives its own.
    var record: KeepAwakeSessionRecord? {
        isAutomatic ? nil : KeepAwakeSessionRecord(end: end, minutes: minutes)
    }

    /// Extends from the later of the old end and now, so an expired-but-unreaped end never shortens it.
    mutating func extend(byMinutes minutes: Int, now: Date) -> Bool {
        guard let end, minutes > 0 else { return false }
        self.end = max(end, now).addingTimeInterval(Double(minutes * 60))
        self.minutes = (self.minutes ?? 0) + minutes
        return true
    }
}

struct KeepAwakeSessionRecord: Codable, Sendable, Equatable {
    var end: Date?
    var minutes: Int?

    func restored(now: Date) -> KeepAwakeSession? {
        if let end, end <= now { return nil }
        return KeepAwakeSession(trigger: .manual, end: end, minutes: minutes)
    }

    static func load(from defaults: UserDefaults) -> Self? {
        defaults.data(forKey: KeepAwakeSettings.Key.session).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    static func save(_ record: Self?, to defaults: UserDefaults) {
        guard let record, let data = try? JSONEncoder().encode(record) else {
            return defaults.removeObject(forKey: KeepAwakeSettings.Key.session)
        }
        defaults.set(data, forKey: KeepAwakeSettings.Key.session)
    }
}

enum KeepAwakeEndReason: Sendable, Equatable {
    case manual, timer, battery, quit, automation
}
