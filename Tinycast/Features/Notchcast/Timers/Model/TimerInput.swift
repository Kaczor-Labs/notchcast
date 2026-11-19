import Foundation

/// What Start Timer was given: when it ends, whether that is a clock time, and its label.
struct TimerRequest: Equatable, Sendable {
    var end: Date
    var label: String
    var isAlarm: Bool
}

enum TimerInputError: Error, Equatable, Sendable {
    case unreadable
    case tooLong
}

/// `25` is minutes, `1h30m`, `90s` and `2h` carry units, `07:30` is the next such clock time.
enum TimerInput {
    static let defaultSeconds: TimeInterval = 15 * 60
    static let maximumSeconds: TimeInterval = 99 * 3600
    static let labelLimit = 40

    static func parse(_ text: String, now: Date, calendar: Calendar) -> Result<TimerRequest, TimerInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = String(trimmed.prefix { !$0.isWhitespace })
        let label = String(trimmed.dropFirst(time.count).trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(labelLimit)).trimmingCharacters(in: .whitespaces)
        if time.isEmpty { return .success(TimerRequest(end: now + defaultSeconds, label: "", isAlarm: false)) }
        if time.contains(":") {
            guard let end = alarm(time, after: now, calendar: calendar) else { return .failure(.unreadable) }
            return .success(TimerRequest(end: end, label: label, isAlarm: true))
        }
        guard let seconds = duration(time), seconds > 0 else { return .failure(.unreadable) }
        guard seconds <= maximumSeconds else { return .failure(.tooLong) }
        return .success(TimerRequest(end: now + seconds, label: label, isAlarm: false))
    }

    /// Units in h, m, s order, each at most once; a bare number is minutes.
    static func duration(_ token: String) -> TimeInterval? {
        let token = token.lowercased()
        if isDigits(token) { return Int(token).map { TimeInterval($0) * 60 } }
        let units: [(Character, TimeInterval)] = [("h", 3600), ("m", 60), ("s", 1)]
        var total: TimeInterval = 0
        var digits = ""
        var next = 0
        for character in token {
            if isDigits(String(character)) {
                digits.append(character)
                continue
            }
            guard let index = units[next...].firstIndex(where: { $0.0 == character }), let value = Int(digits)
            else { return nil }
            total += TimeInterval(value) * units[index].1
            next = index + 1
            digits = ""
        }
        return digits.isEmpty && next > 0 ? total : nil
    }

    /// 24-hour `H:MM` or `HH:MM`; a time already passed today, or this very minute, means tomorrow.
    static func alarm(_ token: String, after now: Date, calendar: Calendar) -> Date? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              isDigits(parts[0]), isDigits(parts[1]),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60
        else { return nil }
        return calendar.nextDate(
            after: now, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
