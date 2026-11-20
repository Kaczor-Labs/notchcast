// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Timers/TimersAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Timers/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Timers/Service/*.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit

/// #926 acceptance on a fake clock: a timer ticks in the pill, rings with its label, survives a relaunch.
@main
@MainActor
enum TimersModuleTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        countdownRings()
        nearestAndMenu()
        relaunch()
        zoneChange()
        stopTimer()
        badInput()
        launcherDispatch()
        print("\(checks) timer module checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    /// Acceptance 1: `Start Timer 1m tea` counts down in the island and rings with "tea" after a minute.
    static func countdownRings() {
        let rig = Rig()
        defer { rig.close() }
        let module = rig.module()
        module.start()
        module.start("1m tea")
        check("the start is confirmed", rig.island.posts.last?.id == "timers.started")
        check("the pill shows a minute", rig.island.status?.text == "1:00" && rig.island.status?.symbol == "timer")
        check("the pill reads the label", rig.island.status?.label.hasPrefix("tea, ") == true)
        check("the end date is stored", TimerStore(defaults: rig.defaults).load().map(\.label) == ["tea"])
        rig.now += 30
        module.refresh()
        check("it ticks down", rig.island.status?.text == "0:30" && rig.chimes == 0)
        rig.now += 30
        module.refresh()
        guard let ring = rig.island.posts.last else { return check("it rings", false) }
        check("at zero it pops out with the label", ring.text == "tea" && ring.id.hasPrefix("timers.ring."))
        check("and stays until dismissed", ring.seconds == TimersModule.ringSeconds && !ring.isFailure)
        check("a sound plays once", rig.chimes == 1)
        check("the pill countdown clears", rig.island.status == nil)
        check("it leaves the store", TimerStore(defaults: rig.defaults).load().isEmpty)
        check("the menu offers to dismiss it", rig.island.rows.map(\.title) == ["Dismiss tea"])
        module.refresh()
        check("a ring is never repeated", rig.chimes == 1 && rig.island.posts.filter { $0.id == ring.id }.count == 1)
        rig.island.taps[ring.id]?()
        check("a tap dismisses it", rig.island.ended == [ring.id] && rig.island.rows.isEmpty)
    }

    /// Several run at once: the pill shows the nearest, the menu lists all and stops the one chosen.
    static func nearestAndMenu() {
        let rig = Rig()
        defer { rig.close() }
        let module = rig.module()
        module.start()
        module.start("5m later")
        module.start("90s sooner")
        check("the nearest shows", rig.island.status?.text == "1:30"
              && rig.island.status?.label.hasPrefix("sooner, ") == true)
        check("the open island lists all with labels, soonest first",
              rig.island.rows.map(\.title).map { $0.hasPrefix("Stop sooner") || $0.hasPrefix("Stop later") }
                == [true, true] && rig.island.rows.first?.title.hasPrefix("Stop sooner") == true)
        let rows = rig.island.rows.count
        rig.island.select(rig.island.rows[0].id)
        check("a row stops its timer", rig.island.rows.count == rows - 1 && rig.island.status?.text == "5:00")
        check("the store follows", TimerStore(defaults: rig.defaults).load().map(\.label) == ["later"])
        module.start("07:30 wake")
        check("an alarm 23h30m away waits behind the nearer timer", rig.island.status?.text == "5:00")
        rig.now += 301
        module.refresh()
        check("the alarm is next", rig.island.status?.text == "24h" && rig.island.status?.symbol == "alarm")
        module.stop()
        check("switching off clears the pill, the menu and the ring", rig.island.status == nil
              && rig.island.rows.isEmpty && rig.island.ended.contains { $0.hasPrefix("timers.ring.") })
        check("but keeps the alarm for the next start",
              TimerStore(defaults: rig.defaults).load().map(\.label) == ["wake"])
    }

    /// Timers outlive a relaunch; one that ended while closed is reported once, without a sound.
    static func relaunch() {
        let rig = Rig()
        defer { rig.close() }
        let first = rig.module()
        first.start()
        first.start("2m tea")
        first.stop()
        rig.now += 60
        let second = rig.module()
        second.start()
        check("a relaunch resumes from the stored end", rig.island.status?.text == "1:00")
        second.stop()
        rig.now += 300
        let posts = rig.island.posts.count
        let third = rig.module()
        third.start()
        let missed = rig.island.posts.dropFirst(posts)
        check("one that ended while closed is reported",
              missed.count == 1 && missed.first?.text.hasPrefix("tea ended at ") == true)
        check("as a ring without a sound", rig.chimes == 0 && missed.first?.seconds == TimersModule.ringSeconds)
        check("nothing ticks", rig.island.status == nil)
        third.stop()
        let again = rig.island.posts.count
        let fourth = rig.module()
        fourth.start()
        check("and reported only once", rig.island.posts.count == again)
        fourth.stop()
    }

    /// #1096 live: a zone change while running moves the alarm to the same clock time on the next pass.
    static func zoneChange() {
        let rig = Rig()
        defer { rig.close() }
        let module = rig.module()
        module.start()
        module.start("07:30 wake")
        guard let wake = TimerStore(defaults: rig.defaults).load().first else { return check("alarm set", false) }
        rig.zone = TimeZone(identifier: "Europe/London")!
        module.refresh()
        let moved = TimerStore(defaults: rig.defaults).load().first
        check("the running alarm follows to 07:30 London", moved?.end == wake.end + 3600
              && moved?.zone == "Europe/London")
        rig.now = wake.end
        module.refresh()
        check("so 07:30 Warsaw passes without a ring", rig.chimes == 0 && rig.island.status?.text == "1h00")
        rig.now = wake.end + 3600
        module.refresh()
        check("and it rings at 07:30 London", rig.chimes == 1)
        module.stop()
    }

    static func stopTimer() {
        let rig = Rig()
        defer { rig.close() }
        let module = rig.module()
        module.start()
        module.stopAll()
        check("Stop Timer with nothing running says so", rig.island.posts.last?.text == "No timer running")
        module.start("1m")
        module.start("2m")
        module.start("10s")
        rig.now += 10
        module.refresh()
        module.stopAll()
        check("Stop Timer cancels every timer and ring", rig.island.posts.last?.text == "3 timers stopped"
              && rig.island.status == nil && rig.island.rows.isEmpty
              && TimerStore(defaults: rig.defaults).load().isEmpty)
        check("the ring is taken down", rig.island.ended.count == 1)
    }

    static func badInput() {
        let rig = Rig()
        defer { rig.close() }
        let module = rig.module()
        module.start()
        module.start("tea")
        check("an unreadable time is a failure", rig.island.posts.last?.isFailure == true && rig.island.status == nil)
        module.start("100h")
        check("past 99 hours says so", rig.island.posts.last?.text == "Timers run up to 99 hours")
        module.stop()
        module.start("1m")
        check("a stopped module takes nothing", TimerStore(defaults: rig.defaults).load().isEmpty)
    }

    /// The hook path: the launcher hands the inline field's text to Start Timer; a hotkey runs it bare.
    static func launcherDispatch() {
        let rig = Rig()
        defer { rig.close() }
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("timers never install a tap")
        }
        let controller = NotchcastController(
            addons: [TimersAddon.self], defaults: rig.defaults, hub: hub, dictation: FakeDictation(),
            presenter: rig.island, now: { rig.now })
        controller.start()
        check("off by default", !controller.submit(entryID: "command:nc-start-timer", argument: "1m"))
        controller.stop()
        controller.preferences.set("liveTimers", on: true)
        controller.start()
        check("the v1 ids stay", TimersAddon.switches.map(\.id) == ["liveTimers"]
              && controller.enabledCommands.map(\.id) == ["command:nc-start-timer", "command:nc-stop-timer"])
        check("typed text reaches the timer", controller.submit(entryID: "command:nc-start-timer", argument: "1m tea")
              && rig.island.status?.text == "1:00" && rig.island.rows.first?.title.hasPrefix("Stop tea") == true)
        check("a bare run starts the default", controller.run(entryID: "command:nc-start-timer")
              && rig.island.rows.count == 2 && rig.island.rows.last?.title.hasPrefix("Stop Timer") == true)
        check("Stop Timer runs", controller.run(entryID: "command:nc-stop-timer") && rig.island.rows.isEmpty)
        controller.stop()
    }
}

@MainActor
final class Rig {
    let suite = "nc-timers-module-test.\(UUID().uuidString)"
    let defaults: UserDefaults
    let island = TimersPresenter()
    var now: Date
    var zone = TimeZone(identifier: "Europe/Warsaw")!
    var chimes = 0

    init() {
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8))!
    }

    func module() -> TimersModule {
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("timers never install a tap")
        }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: TimersAddon.switches),
            presenter: island, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { [unowned self] in now }, onTapsChanged: {})
        // The tick never wakes on its own: each check calls `refresh` after moving the clock.
        let environment = TimersModule.Environment(
            calendar: { [unowned self] in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                return calendar
            }, sleep: { [unowned self] _ in try await park() },
            chime: { [unowned self] in chimes += 1 })
        return TimersModule(context: context, environment: environment)
    }

    /// A wait only cancellation ends: the stream stays open while its continuation is held here.
    private var parked: [AsyncStream<Void>.Continuation] = []

    func park() async throws {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        parked.append(continuation)
        for await _ in stream {}
        try Task.checkCancellation()
    }

    func close() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
final class TimersPresenter: IslandPresenting {
    private(set) var posts: [IslandNotice] = []
    private(set) var ended: [String] = []
    private(set) var status: IslandStatus?
    private(set) var rows: [IslandMenuRow] = []
    private(set) var taps: [String: @MainActor () -> Void] = [:]
    private var onSelect: (@MainActor (String) -> Void)?

    func showLevel(_ level: IslandLevel) {}

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps[notice.id] = onTap
    }

    func end(notice id: String) { ended.append(id) }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        precondition(id == TimersModule.statusID && (status == nil || status?.id == id))
        self.status = status
    }

    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        precondition(owner == TimersModule.menuOwner)
        self.rows = rows
        self.onSelect = onSelect
    }

    func select(_ id: String) { onSelect?(id) }
}
