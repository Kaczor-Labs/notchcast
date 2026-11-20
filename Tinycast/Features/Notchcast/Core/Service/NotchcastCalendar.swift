import Foundation

/// One calendar occurrence, as stock Calendar holds it.
struct NotchcastEvent: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

/// Stock Calendar behind the core's door: the events it holds and its My Schedule screen.
struct NotchcastCalendar {
    var events: @MainActor () -> [NotchcastEvent] = { [] }
    var showSchedule: @MainActor () -> Void = {}
}

extension NotchcastContext {
    var calendar: NotchcastCalendar { services.calendar }
}
