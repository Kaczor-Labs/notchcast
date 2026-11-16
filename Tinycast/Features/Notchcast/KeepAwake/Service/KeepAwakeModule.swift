import Foundation
import Observation

/// Keep Awake (F108) and Lid Closed (F109); `disablesleep 1` is only ever set while assertions are held.
@MainActor
@Observable
final class KeepAwakeModule: NotchcastModule {
    static let switchID = "keepAwake"
    static let lidSwitchID = "lidClosedAwake"
    static let statusOwner = "keepAwake"
    /// Backs up the battery notifications, which macOS coalesces.
    static let batteryWatch: TimeInterval = 30

    private(set) var session: KeepAwakeSession?
    private(set) var isPaused = false

    @ObservationIgnored private let context: NotchcastContext
    @ObservationIgnored private let system: KeepAwakeSystem
    @ObservationIgnored private let helpers: KeepAwakeHelperTracker
    @ObservationIgnored private var settings: KeepAwakeSettings
    @ObservationIgnored private var assertionIDs: [UInt32] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored private var inFlight: (verb: KeepAwakeSleepVerb, operation: UUID)?
    @ObservationIgnored private var backoff = KeepAwakeRetryBackoff()
    @ObservationIgnored private var helperFailureShown = false
    /// Set when the person turns off a session automation started, until its conditions lapse.
    @ObservationIgnored private var automationSuppressed = false

    init(context: NotchcastContext, system: KeepAwakeSystem) {
        self.context = context
        self.system = system
        helpers = KeepAwakeHelperTracker(system: system)
        settings = KeepAwakeSettings(defaults: context.defaults)
    }

    var isHolding: Bool { !assertionIDs.isEmpty }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        system.screenLock.start { [weak self] locked in self?.screenLockChanged(locked) }
        system.sensors.start { [weak self] in self?.sensorsChanged() }
        let record = KeepAwakeSessionRecord.load(from: context.defaults)
        if settings.restoresSession, let restored = record?.restored(now: context.now()) {
            session = restored
            isPaused = settings.pausesWhenLocked && system.screenLock.isLocked
        } else {
            KeepAwakeSessionRecord.save(nil, to: context.defaults)
        }
        adoptStaleHelpers()
        observeLidSwitch()
        evaluateAutomation()
        apply()
    }

    /// Runs synchronously at quit too; a switch still on means the app is quitting, not the person.
    func stop() {
        guard running else { return }
        let reason: KeepAwakeEndReason = context.isEnabled(Self.switchID) ? .quit : .manual
        running = false
        end(reason)
        syncHelper()
        system.screenLock.stop()
        system.sensors.stop()
        scheduleNext()
        context.presenter.setStatus(nil, for: Self.statusOwner, onTap: nil)
    }

    // MARK: - Commands

    func toggle() {
        guard running else { return }
        guard let session else { return begin(.manual(minutes: settings.minutes, now: context.now())) }
        if session.isAutomatic { automationSuppressed = true }
        end(.manual)
    }

    func extend() {
        guard running else { return }
        let minutes = settings.minutes > 0 ? settings.minutes : KeepAwakeSettings.defaultMinutes
        guard var extended = session else { return begin(.manual(minutes: minutes, now: context.now())) }
        guard extended.extend(byMinutes: minutes, now: context.now()) else {
            return post(String(localized: "Keep Awake On", table: "NotchcastKeepAwake"), detail: describe(extended))
        }
        session = extended
        KeepAwakeSessionRecord.save(extended.record, to: context.defaults)
        post(String(localized: "Keep Awake Extended", table: "NotchcastKeepAwake"), detail: describe(extended))
        apply()
    }

    /// The settings rows write the suite directly; this rereads it.
    func settingsChanged() {
        settings = KeepAwakeSettings(defaults: context.defaults)
        guard running else { return }
        if session?.isAutomatic == false { KeepAwakeSessionRecord.save(session?.record, to: context.defaults) }
        isPaused = session != nil && settings.pausesWhenLocked && system.screenLock.isLocked
        evaluateAutomation()
        apply()
    }

    // MARK: - Sessions

    private func begin(_ new: KeepAwakeSession) {
        session = new
        isPaused = settings.pausesWhenLocked && system.screenLock.isLocked
        KeepAwakeSessionRecord.save(new.record, to: context.defaults)
        apply()
        if !new.isAutomatic, session == new {
            post(String(localized: "Keep Awake On", table: "NotchcastKeepAwake"), detail: describe(new))
        }
    }

    private func end(_ reason: KeepAwakeEndReason) {
        guard session != nil else { return }
        session = nil
        isPaused = false
        if reason != .quit { KeepAwakeSessionRecord.save(nil, to: context.defaults) }
        setHolding(false)
        guard running else { return }
        switch reason {
        case .manual: post(String(localized: "Keep Awake Off", table: "NotchcastKeepAwake"))
        case .timer: post(String(localized: "Keep Awake Ended", table: "NotchcastKeepAwake"))
        case .battery:
            post(
                String(localized: "Battery Low", table: "NotchcastKeepAwake"),
                detail: String(localized: "Keep Awake turned off to save battery.", table: "NotchcastKeepAwake"),
                isFailure: true)
        case .quit, .automation: break
        }
        apply()
    }

    /// Every input funnels here; it converges assertions, the helper, the timer and the status.
    private func apply() {
        guard running else { return }
        let now = context.now()
        let battery = system.sensors.battery()
        if let session {
            let policy = KeepAwakePolicy(enabled: true, until: session.end, floor: settings.batteryFloor)
            switch policy.evaluate(now: now, onBattery: battery.onBattery, percent: battery.percent) {
            case .expired: return end(.timer)
            case .batteryFloor: return end(.battery)
            case .off, .hold: break
            }
        }
        setHolding(session != nil && !isPaused)
        syncHelper()
        scheduleNext()
        let symbol = isPaused ? "cup.and.saucer" : "cup.and.saucer.fill"
        let label = String(localized: "Keep Awake", table: "NotchcastKeepAwake")
        context.presenter.setStatus(
            session.map { _ in IslandStatus(id: Self.statusOwner, symbol: symbol, text: nil, label: label) },
            for: Self.statusOwner, onTap: nil)
    }

    private func setHolding(_ wanted: Bool) {
        if !wanted {
            try? KeepAwakeAssertionPlan.release(assertionIDs, run: system.assertions.release)
            assertionIDs = []
            return
        }
        guard assertionIDs.isEmpty else { return }
        do {
            assertionIDs = try KeepAwakeAssertionPlan.acquire(
                types: KeepAwakePolicy().assertionTypes, create: system.assertions.create,
                release: system.assertions.release)
        } catch {
            session = nil
            KeepAwakeSessionRecord.save(nil, to: context.defaults)
            post(String(localized: "Couldn't Keep Awake", table: "NotchcastKeepAwake"), isFailure: true)
        }
    }

    /// The fire holds the module, so a stopped one lives until its recovery retry has run.
    private func scheduleNext() {
        let now = context.now()
        var due: [Date] = []
        if let end = session?.end { due.append(end) }
        if session != nil, settings.batteryFloor > 0, system.sensors.battery().onBattery {
            due.append(now + Self.batteryWatch)
        }
        if let retry = runnableRetry() { due.append(retry) }
        guard let next = due.min() else { return system.scheduler.cancel() }
        system.scheduler.schedule(after: .seconds(max(0, next.timeIntervalSince(now)))) { [self] in
            if running { apply() } else { syncHelper() }
        }
    }

    // MARK: - Lid Closed

    /// A stopped module keeps recovering until a newer one takes the add-on over.
    private var ownsJournal: Bool { running || context.module.map { $0 === self } ?? true }

    private var plannedVerb: KeepAwakeSleepVerb {
        LidClosedPolicy.plan(
            enabled: running && context.isEnabled(Self.lidSwitchID), helperReady: system.helper.isInstalled,
            keepAwakeHolding: isHolding)
    }

    /// Drops a backoff whose verb is no longer the one to run, so a stale retry never fires.
    private func runnableRetry() -> Date? {
        guard ownsJournal, let verb = backoff.verb, let retry = backoff.retryAt else { return nil }
        guard plannedVerb == verb, system.journal.current.canRun(verb) else {
            backoff.reset()
            return nil
        }
        return inFlight == nil ? retry : nil
    }

    /// Also replays a journal a crash left dirty; with the switch off, `KeepAwakeRecovery` does.
    private func syncHelper() {
        let undo = KeepAwakeSleepJournal.undo
        guard ownsJournal else { return }
        if let inFlight, running || inFlight.verb == undo { return }
        let verb = plannedVerb
        var journal = system.journal.current
        guard journal.canRun(verb), backoff.isDue(verb, now: context.now()) else { return }
        let operation = UUID()
        journal.begin(verb, operation: operation)
        do {
            try system.journal.store(journal)
        } catch {
            backoff.fail(verb, now: context.now())
            showHelperFailure()
            guard verb == undo else { return scheduleNext() }
        }
        inFlight = (verb, operation)
        helpers.send(verb, sleepWanted: { [self] in plannedVerb != undo }, exited: helperExited) { [self] result in helperReplied(verb, operation, result) }
    }

    /// An earlier run's helper may still land its verb, so the journal stays dirty until it exits.
    private func adoptStaleHelpers() {
        var journal = system.journal.current
        let stale = helpers.stale(in: journal)
        journal.relaunch(stale: stale)
        if !stale.isEmpty { try? system.journal.store(journal) }
        helpers.watch(stale) { [self] helper in helperExited(helper) }
    }

    private func helperExited(_ helper: KeepAwakeHelperID) {
        guard ownsJournal else { return helpers.cancelWatches() }
        var journal = system.journal.current
        journal.lost(helper)
        try? system.journal.store(journal)
        syncHelper()
    }

    /// Holds the module past `stop()`, so a switch-off still records its `disablesleep 0`.
    private func helperReplied(_ verb: KeepAwakeSleepVerb, _ operation: UUID, _ result: KeepAwakeHelperResult) {
        let undo = KeepAwakeSleepJournal.undo
        guard ownsJournal, inFlight?.operation == operation else { return }
        inFlight = nil
        var journal = system.journal.current
        switch result {
        case .ok: journal.succeed(verb, operation: operation)
        case .unsupported where verb == undo: journal.release(operation: operation)
        case .unsupported, .failed: break
        }
        let settled = result == .ok || (result == .unsupported && verb == undo)
        if settled, (try? system.journal.store(journal)) != nil {
            backoff.reset()
            helperFailureShown = false
        } else {
            backoff.fail(verb, now: context.now())
            showHelperFailure()
        }
        if result == .ok, verb == undo, !journal.isDirty, lidSleepWanted, system.lid.isClosed {
            system.lid.requestSleep { [self] in lidSleepWanted }
        }
        syncHelper()
        if running { apply() } else { scheduleNext() }
    }

    /// Read on every retry, so a newer module or a new session withdraws the request.
    private var lidSleepWanted: Bool { ownsJournal && session == nil && !isHolding && inFlight == nil }

    private func showHelperFailure() {
        guard running, !helperFailureShown else { return }
        helperFailureShown = true
        post(
            String(localized: "Lid Setting Failed", table: "NotchcastKeepAwake"),
            detail: String(localized: "Notchcast will try again.", table: "NotchcastKeepAwake"),
            isFailure: true)
    }

    private func observeLidSwitch() {
        guard running else { return }
        _ = withObservationTracking {
            context.isEnabled(Self.lidSwitchID)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeLidSwitch()
                self?.syncHelper()
            }
        }
    }

    // MARK: - Screen lock and automation

    private func screenLockChanged(_ locked: Bool) {
        guard running, session != nil else { return }
        isPaused = settings.pausesWhenLocked && locked
        evaluateAutomation()
        apply()
    }

    private func sensorsChanged() {
        guard running else { return }
        evaluateAutomation()
        apply()
    }

    private func evaluateAutomation() {
        let conditions = settings.automation
        guard conditions.isAnyEnabled else {
            automationSuppressed = false
            if session?.isAutomatic == true { end(.automation) }
            return
        }
        let facts = system.sensors.automationFacts()
        if !conditions.areSatisfied(by: facts) { automationSuppressed = false }
        switch KeepAwakeAutomation.action(
            conditions: conditions, facts: facts, sessionActive: session != nil,
            automaticSessionActive: session?.isAutomatic == true)
        {
        case .activate where !automationSuppressed: begin(.automatic)
        case .deactivate: end(.automation)
        case .activate, .none: break
        }
    }

    // MARK: - Presentation

    private func post(_ title: String, detail: String? = nil, isFailure: Bool = false) {
        let text = [title, detail].compactMap(\.self).joined(separator: "\n")
        let notice = IslandNotice(
            id: Self.statusOwner, symbol: isFailure ? "exclamationmark.triangle" : "checkmark", text: text,
            progress: nil, isFailure: isFailure)
        context.presenter.post(notice, onTap: nil)
    }

    private func describe(_ session: KeepAwakeSession) -> String {
        guard let end = session.end else { return String(localized: "Until turned off", table: "NotchcastKeepAwake") }
        let time = end.formatted(date: .omitted, time: .shortened)
        return String(localized: "Until \(time)", table: "NotchcastKeepAwake")
    }
}
