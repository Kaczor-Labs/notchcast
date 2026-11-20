// notchcast-sources: Tinycast/Features/Notchcast/Timers/Model/*.swift
import Foundation

/// #926: what Start Timer reads, the pill's countdown text, and the end-date store, on a fixed clock.
@main
@MainActor
enum TimersModelTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func main() {
        durations()
        alarms()
        labels()
        clockText()
        clockChanges()
        store()
        travel()
        print("\(checks) timer model checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func parse(_ text: String, now: Date = date(18, 8, 0)) -> Result<TimerRequest, TimerInputError> {
        TimerInput.parse(text, now: now, calendar: calendar)
    }

    static func seconds(_ text: String) -> TimeInterval? {
        guard case .success(let request) = parse(text), !request.isAlarm else { return nil }
        return request.end.timeIntervalSince(date(18, 8, 0))
    }

    static func durations() {
        check("empty starts the default 15 minutes", seconds("") == 900 && seconds("   ") == 900)
        check("a bare number is minutes", seconds("25") == 1500)
        check("hours and minutes", seconds("1h30m") == 5400)
        check("seconds", seconds("90s") == 90)
        check("hours", seconds("2h") == 7200)
        check("all three units", seconds("1h2m3s") == 3723)
        check("units ignore case", seconds("1H30M") == 5400)
        check("99 hours is the most", seconds("99h") == 99 * 3600 && seconds("5940") == 99 * 3600)
        check("past 99 hours is refused", parse("100h") == .failure(.tooLong) && parse("99h1s") == .failure(.tooLong))
        check("past 99 hours in minutes is refused", parse("5941") == .failure(.tooLong))
        for bad in ["0", "0m", "abc", "1h30", "1m1h", "1sm", "1hh", "-5", "+5", "1.5", "h", "m5", "1 h"] {
            let result = parse(bad)
            let refused = result == .failure(.unreadable) || (bad == "1 h" && seconds(bad) == 60)
            check("\"\(bad)\" is not a duration (\(result))", refused)
        }
        check("an overflowing number is refused", parse("99999999999999999999999") == .failure(.unreadable))
    }

    static func alarms() {
        guard case .success(let early) = parse("07:30") else { return check("07:30 parses", false) }
        check("07:30 at 08:00 sets tomorrow 07:30", early.isAlarm && early.end == date(19, 7, 30))
        guard case .success(let later) = parse("09:15") else { return check("09:15 parses", false) }
        check("a time still ahead is today", later.end == date(18, 9, 15))
        guard case .success(let now) = parse("08:00") else { return check("08:00 parses", false) }
        check("this very minute is tomorrow", now.end == date(19, 8, 0))
        guard case .success(let short) = parse("7:05") else { return check("7:05 parses", false) }
        check("a one-digit hour reads", short.end == date(19, 7, 5))
        guard case .success(let midnight) = parse("00:00") else { return check("00:00 parses", false) }
        check("midnight is the coming one", midnight.end == date(19, 0, 0))
        for bad in ["24:00", "07:60", "7:5", "007:30", "07:30:00", ":30", "07:", "ab:cd", "07:3a"] {
            check("\"\(bad)\" is not a clock time", parse(bad) == .failure(.unreadable))
        }
    }

    static func labels() {
        guard case .success(let tea) = parse("1m tea") else { return check("1m tea parses", false) }
        check("1m tea is a minute labelled tea", tea.label == "tea" && tea.end == date(18, 8, 1) && !tea.isAlarm)
        guard case .success(let spaced) = parse("  1m   tea  time  ") else { return check("spaced parses", false) }
        check("the label keeps inner spaces, trims the ends", spaced.label == "tea  time")
        guard case .success(let wake) = parse("07:30 wake up") else { return check("alarm label parses", false) }
        check("an alarm takes a label", wake.label == "wake up" && wake.isAlarm)
        let long = String(repeating: "x", count: 39) + " " + String(repeating: "y", count: 10)
        guard case .success(let capped) = parse("5 " + long) else { return check("long label parses", false) }
        check("a label keeps 40 characters", capped.label == String(long.prefix(39)))
        guard case .success(let exact) = parse("5 " + String(repeating: "z", count: 45)) else {
            return check("45 characters parse", false)
        }
        check("a label stops at 40", exact.label.count == 40)
        check("an empty input has no label", (try? parse("").get().label) == "")
    }

    static func clockText() {
        let cases: [(TimeInterval, String)] = [
            (0.2, "0:01"), (1, "0:01"), (59, "0:59"), (60, "1:00"), (61, "1:01"), (599, "9:59"),
            (599.5, "10m"), (600, "10m"), (601, "11m"), (1500, "25m"), (3540, "59m"), (3541, "1h00"),
            (3600, "1h00"), (3601, "1h01"), (5400, "1h30"), (35_940, "9h59"), (35_941, "10h"),
            (36_000, "10h"), (36_001, "11h"), (99 * 3600, "99h"), (0, "0:00"), (-5, "0:00"),
            (.infinity, "99h"), (.nan, "0:00"), (500 * 3600, "99h"),
        ]
        for (remaining, text) in cases {
            check("\(remaining) s reads \(text), got \(TimerClock.text(remaining: remaining))",
                  TimerClock.text(remaining: remaining) == text)
        }
        var longest = 0
        for remaining in stride(from: 0.0, through: 99 * 3600, by: 7) {
            longest = max(longest, TimerClock.text(remaining: remaining).count)
        }
        check("never more than four characters, the status limit (\(longest))", longest <= 4)
    }

    /// The tick sleeps exactly until the text changes: never past a change, never short of one.
    static func clockChanges() {
        check("an ended timer wakes at once", TimerClock.untilChange(remaining: 0) == 0)
        check("the last second wakes at zero", TimerClock.untilChange(remaining: 0.5) == 0.5)
        check("seconds tick each second", TimerClock.untilChange(remaining: 90.25) == 0.25)
        check("minutes wait for the minute", TimerClock.untilChange(remaining: 1500) == 60)
        check("10m waits for 9:59", TimerClock.untilChange(remaining: 600) == 1)
        check("12h waits for 11h", TimerClock.untilChange(remaining: 40_000) == 400)
        var seed: UInt64 = 926
        var bad: [TimeInterval] = []
        for _ in 0..<5000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let remaining = TimeInterval((seed >> 33) % UInt64(99 * 3600)) + [0, 0.25, 0.5][Int(seed % 3)] + 0.25
            let wait = TimerClock.untilChange(remaining: remaining)
            let now = TimerClock.text(remaining: remaining)
            if !(wait > 0 && TimerClock.text(remaining: remaining - wait) != now
                 && TimerClock.text(remaining: remaining - wait + 0.125) == now) { bad.append(remaining) }
        }
        check("each wait lands on the next change (\(bad.prefix(5)))", bad.isEmpty)
    }

    static func store() {
        let suite = "nc-timers-model-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TimerStore(defaults: defaults)
        check("a fresh store holds nothing", store.load().isEmpty)
        let now = date(18, 8, 0)
        let later = TimerEntry(id: UUID(), end: now + 600, label: "tea", isAlarm: false)
        let sooner = TimerEntry(id: UUID(), end: now + 60, label: "", isAlarm: false)
        let alarm = TimerEntry(id: UUID(), end: date(19, 7, 30), label: "wake", isAlarm: true)
        store.save([later, sooner, alarm])
        check("absolute end dates round-trip", store.load() == [later, sooner, alarm])
        check("raw storage is end dates, not durations", defaults.data(forKey: TimerStore.key) != nil)

        let relaunch = store.resume(at: now + 30, calendar: calendar)
        check("a relaunch before any end resumes all, soonest first", relaunch.running == [sooner, later, alarm]
              && relaunch.missed.isEmpty && store.load().count == 3)
        let afterQuit = store.resume(at: now + 120, calendar: calendar)
        check("one that ended while closed is reported", afterQuit.missed == [sooner]
              && afterQuit.running == [later, alarm])
        check("and leaves the store", store.load() == [later, alarm])
        check("so it is reported once", store.resume(at: now + 120, calendar: calendar).missed.isEmpty)
        check("an end exactly now has ended", store.resume(at: now + 600, calendar: calendar).missed == [later])

        store.save([])
        check("an empty list removes the key", defaults.object(forKey: TimerStore.key) == nil)
        defaults.set(Data("not json".utf8), forKey: TimerStore.key)
        check("unreadable data counts as none", store.load().isEmpty && store.resume(at: now, calendar: calendar).missed.isEmpty)
        defaults.set("a string", forKey: TimerStore.key)
        check("a wrong type counts as none", store.load().isEmpty)
    }

    /// #1096: an alarm set for 07:30 rings at 07:30 wherever the clock now is, a timer keeps its instant.
    static func travel() {
        let suite = "nc-timers-model-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TimerStore(defaults: defaults)
        var london = calendar
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let now = date(18, 8, 0)
        let alarm = TimerEntry(id: UUID(), end: date(19, 7, 30), label: "", isAlarm: true,
                               zone: calendar.timeZone.identifier)
        let timer = TimerEntry(id: UUID(), end: now + 600, label: "", isAlarm: false)
        let moved = alarm.following(london)
        check("after a zone change west the alarm rings at 07:30 there",
              london.dateComponents([.day, .hour, .minute], from: moved.end) == DateComponents(day: 19, hour: 7, minute: 30)
              && moved.end == date(19, 7, 30) + 3600 && moved.zone == "Europe/London")
        check("and moves once", moved.following(london) == moved)
        check("the same zone leaves it alone", alarm.following(calendar) == alarm)
        check("a timer keeps its instant", timer.following(london) == timer)
        let legacy = TimerEntry(id: UUID(), end: date(19, 7, 30), label: "", isAlarm: true)
        check("an alarm saved without a zone keeps its instant", legacy.following(london) == legacy)

        store.save([alarm, timer])
        let resumed = store.resume(at: now, calendar: london)
        check("a relaunch in the new zone moves the alarm and saves it",
              resumed.running == [timer, moved] && store.load() == [timer, moved])
        store.save([alarm])
        check("an alarm the move pushes past now is not missed",
              store.resume(at: date(19, 7, 45), calendar: london).missed.isEmpty)
    }
}
