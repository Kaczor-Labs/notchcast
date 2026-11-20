// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's notch calendar: a day's events in order, the next one, a start as text.

import Foundation

/// Core's `NotchcastEvent` as Model sees it: that type lives in the Service door, outside Model.
struct DayEvent: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

enum DayAgenda {
    /// The page lists this many events; the rest are counted in one more row.
    static let limit = 5
    private static let hour: TimeInterval = 3600

    /// Today's events not yet over: all-day first, then by start. End dates are exclusive.
    static func today(_ events: [DayEvent], now: Date, calendar: Calendar) -> [DayEvent] {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return [] }
        var seen = Set<String>()
        return events.filter {
            $0.end > $0.start && $0.start < day.end && $0.end > max(day.start, now) && seen.insert($0.id).inserted
        }.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    /// The timed event Home names: the one under way, else the next to start.
    static func next(_ today: [DayEvent]) -> DayEvent? { today.first { !$0.isAllDay } }

    static func isOngoing(_ event: DayEvent, now: Date) -> Bool {
        !event.isAllDay && event.start <= now && event.end > now
    }

    /// "All day", "Now", "in 25 min" inside the hour before a start, else the start's time.
    static func when(_ event: DayEvent, now: Date, calendar: Calendar, locale: Locale) -> String {
        if event.isAllDay { return String(localized: "All day", table: "NotchcastDay") }
        if isOngoing(event, now: now) { return String(localized: "Now", table: "NotchcastDay") }
        let wait = event.start.timeIntervalSince(now)
        guard wait < hour else { return time(event.start, calendar: calendar, locale: locale) }
        let minutes = max(Int((wait / 60).rounded(.up)), 1)
        return String(localized: "in \(minutes) min", table: "NotchcastDay")
    }

    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
