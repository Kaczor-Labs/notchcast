// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's agent support: the percent, the duration and the reset countdown.

import Foundation

/// The reader's region, injected so a harness reads the same text on any machine.
struct AgentsRegion: Equatable, Sendable {
    var locale: Locale
    var timeZone: TimeZone
}

enum AgentsFormat {
    /// Whole percent left, rounded down so a plan never claims more than it has.
    static func percent(_ percentLeft: Double, locale: Locale) -> String {
        let value = percentLeft.isFinite ? min(100, max(0, percentLeft)).rounded(.down) : 0
        return (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "4m", "1h 5m", "2d 3h": never seconds, on a page that redraws once a minute.
    static func duration(_ seconds: TimeInterval, region: AgentsRegion) -> String {
        let seconds = max(60, seconds.isFinite ? seconds : 0)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = seconds >= 3600 ? 2 : 1
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = region.locale
        calendar.timeZone = region.timeZone
        formatter.calendar = calendar
        return formatter.string(from: seconds) ?? ""
    }

    /// The clock time of a reading taken today, with its day once it is older than that.
    static func moment(_ date: Date, now: Date, region: AgentsRegion) -> String {
        let recent = now.timeIntervalSince(date) < 86_400
        var style = Date.FormatStyle(date: recent ? .omitted : .abbreviated, time: .shortened).locale(region.locale)
        style.timeZone = region.timeZone
        return date.formatted(style)
    }
}
