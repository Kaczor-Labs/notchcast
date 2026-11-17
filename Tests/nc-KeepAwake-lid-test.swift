// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeHelperTracker.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap*.swift
// notchcast-sources: Tests/nc-KeepAwake-fixtures.swift
// notchcast-sources: Tests/nc-KeepAwake-machine.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Foundation

@main
@MainActor
enum KeepAwakeLidTests: KeepAwakeHarness {
    static func main() async {
        defer { removeSuites() }
        lidHoldsOnlyWithKeepAwake()
        await lidReleasesOnEveryExit()
        lidCrashJournal()
        lidRetries()
        lidClosedSessionEndRequestsSleep()
        lidStopUndoesAnEnableInFlight()
        lidOldReplyKeepsNewJournal()
        lidStoppedModuleRetriesUndo()
        lidRecoveryNeverGivesUp()
        lidEnableNeedsDurableJournal()
        lidObsoleteReplyNeverSleeps()
        await lidDropsUnrunnableRetry()
        print("nc-KeepAwake-lid-test: all checks passed")
    }

    // MARK: - F109 Lid Closed

    /// A rig with Lid Closed on and a session holding, its `disablesleep 1` acknowledged.
    static func holdingLid(_ defaults: UserDefaults? = nil, configure: (Rig) -> Void = { _ in }) -> Rig {
        let rig = Rig(defaults ?? suite(), lidSwitch: true, configure: configure)
        rig.module.toggle()
        precondition(rig.helper.sent == [.batterySleepOff], "a holding session sends disablesleep 1: \(rig.helper.sent)")
        rig.helper.reply()
        return rig
    }

    static func expectReleased(_ rig: Rig, _ path: String, holding: Bool = false) {
        precondition(rig.held.isEmpty != holding, "\(path): the session holds: \(rig.held)")
        precondition(
            rig.helper.sent == [.batterySleepOff, .batterySleepOn], "\(path): must send disablesleep 0: \(rig.helper.sent)")
        rig.helper.reply()
        precondition(!rig.helper.isWaiting)
    }

    static func lidHoldsOnlyWithKeepAwake() {
        let idle = Rig(suite(), lidSwitch: true)
        precondition(idle.helper.sent.isEmpty, "an idle module with a clean journal never calls the helper")
        idle.module.stop()
        precondition(idle.helper.sent.isEmpty, "a disablesleep 0 we never needed is not ours to send")

        let off = Rig(suite())
        off.module.toggle()
        precondition(off.helper.sent.isEmpty, "Lid Closed off must never send disablesleep 1")

        let missing = Rig(suite(), lidSwitch: true) { $0.helper.isInstalled = false }
        missing.module.toggle()
        precondition(missing.helper.sent.isEmpty, "a missing helper is never called")

        let paused = holdingLid { $0.set(KeepAwakeSettings.Key.pausesWhenLocked, true) }
        paused.screenLock.set(true)
        precondition(paused.helper.sent == [.batterySleepOff, .batterySleepOn], "a paused session lets the lid sleep")
        paused.helper.reply()
        paused.screenLock.set(false)
        precondition(paused.helper.sent.last == .batterySleepOff, "unlocking re-arms Lid Closed")
        paused.helper.reply()

        let busy = Rig(suite(), lidSwitch: true)
        busy.module.toggle()
        busy.module.toggle()
        precondition(busy.helper.sent == [.batterySleepOff], "one helper call at a time")
        busy.helper.reply()
        precondition(busy.helper.sent == [.batterySleepOff, .batterySleepOn], "the queued release runs after the reply")
        busy.helper.reply()
    }

    static func lidReleasesOnEveryExit() async {
        let manual = holdingLid()
        manual.module.toggle()
        expectReleased(manual, "turning Keep Awake off")

        let timed = holdingLid()
        advance(minutes: 60)
        timed.scheduler.run()
        expectReleased(timed, "the timer ending")

        let battery = holdingLid { $0.sensors.power = KeepAwakeBattery(onBattery: true, percent: 40) }
        battery.sensors.power.percent = 19
        battery.sensors.changed?()
        expectReleased(battery, "the battery floor")

        let quit = holdingLid()
        quit.module.stop()
        expectReleased(quit, "quitting")

        let keepAwakeOff = holdingLid()
        keepAwakeOff.preferences.set(KeepAwakeModule.switchID, on: false)
        keepAwakeOff.module.stop()
        expectReleased(keepAwakeOff, "turning the Keep Awake switch off")

        let lidOff = holdingLid()
        lidOff.preferences.set(KeepAwakeModule.lidSwitchID, on: false)
        await Task.yield()
        expectReleased(lidOff, "turning the Lid Closed switch off", holding: true)

        let automatic = holdingLid { $0.set(KeepAwakeSettings.Key.autoPower, true) }
        automatic.module.toggle()
        automatic.helper.reply()
        automatic.helper.sent = []
        automatic.sensors.facts.onPower = false
        automatic.sensors.changed?()
        automatic.sensors.facts.onPower = true
        automatic.sensors.changed?()
        precondition(automatic.helper.sent == [.batterySleepOff])
        automatic.helper.reply()
        automatic.sensors.facts.onPower = false
        automatic.sensors.changed?()
        precondition(automatic.helper.sent == [.batterySleepOff, .batterySleepOn], "automation ending must release")
        automatic.helper.reply()
    }

    static func lidCrashJournal() {
        let applied = suite()
        _ = holdingLid(applied)
        precondition(FakeJournalStore(applied).journal != nil, "disablesleep 1 is journalled")
        let replay = Rig(applied, lidSwitch: true) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        precondition(replay.helper.sent == [.batterySleepOn], "a crash after disablesleep 1 is undone at launch")
        replay.helper.reply()
        precondition(FakeJournalStore(applied).journal == nil, "an acknowledged undo cleans the journal")

        let midCall = suite()
        let crashed = Rig(midCall, lidSwitch: true)
        crashed.module.toggle()
        precondition(crashed.helper.isWaiting, "the crash lands before the helper answers")
        guard let stale = crashed.helper.runningPID else { preconditionFailure("the stalled helper is still alive") }
        let machine = crashed.helper.line.machine
        machine.sleepDisabled = false
        let next = Rig(midCall, lidSwitch: true) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        precondition(next.helper.sent == [.batterySleepOn], "an unanswered disablesleep 1 is undone at launch too")
        next.helper.reply()
        precondition(next.journal.journal != nil, "while the stalled helper lives the journal stays dirty")
        machine.land(.batterySleepOff)
        machine.exit(stale)
        precondition(next.helper.sent == [.batterySleepOn, .batterySleepOn], "its exit re-sends the undo")
        next.helper.reply()
        precondition(next.journal.journal == nil && !machine.sleepDisabled, "the late disablesleep 1 is undone")

        let lidSwitchedOff = suite()
        _ = holdingLid(lidSwitchedOff)
        let withoutLid = Rig(lidSwitchedOff) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        precondition(withoutLid.helper.sent == [.batterySleepOn], "the replay runs even with Lid Closed now off")
        withoutLid.helper.reply()

        let restored = suite()
        _ = holdingLid(restored)
        let resumed = Rig(restored, lidSwitch: true)
        precondition(resumed.held == held && resumed.helper.sent.isEmpty, "a restored session keeps disablesleep 1")
        resumed.module.toggle()
        precondition(resumed.helper.sent == [.batterySleepOn])
        resumed.helper.reply()
    }

    static func lidRetries() {
        let rig = holdingLid()
        rig.module.toggle()
        rig.helper.reply(.failed(1))
        precondition(rig.presenter.notices.last == "Lid Setting Failed")
        precondition(rig.scheduler.delay == .seconds(60), "a failed release retries after a minute")
        advance(minutes: 1)
        rig.scheduler.run()
        precondition(rig.helper.sent == [.batterySleepOff, .batterySleepOn, .batterySleepOn], "the release is retried")
        rig.helper.reply()
        precondition(rig.scheduler.delay == nil, "nothing is left to retry")
    }

    static func lidClosedSessionEndRequestsSleep() {
        let open = holdingLid()
        open.module.toggle()
        open.helper.reply()
        precondition(open.lid.sleepRequests.isEmpty, "an open lid is left alone")

        let closed = holdingLid { $0.lid.isClosed = true }
        closed.module.toggle()
        precondition(closed.lid.sleepRequests.isEmpty, "sleep waits for disablesleep 0 to land")
        closed.helper.reply()
        precondition(closed.lid.sleepRequests.count == 1, "a session ending with the lid closed must request sleep")
        precondition(closed.lid.sleepRequests[0](), "the request stays wanted while idle")
        closed.module.toggle()
        precondition(!closed.lid.sleepRequests[0](), "a new session withdraws the sleep request")
        closed.helper.reply()

        let failed = holdingLid { $0.lid.isClosed = true }
        failed.module.toggle()
        failed.helper.reply(.failed(1))
        precondition(failed.lid.sleepRequests.isEmpty, "no sleep request while disablesleep 1 may still be set")
    }

    // MARK: - Review fixes

    static func lidStopUndoesAnEnableInFlight() {
        let rig = Rig(suite(), lidSwitch: true)
        rig.module.toggle()
        precondition(rig.helper.sent == [.batterySleepOff] && rig.helper.isWaiting)
        rig.switchOff()
        precondition(
            rig.helper.sent == [.batterySleepOff, .batterySleepOn],
            "stopping mid-enable sends its own disablesleep 0: \(rig.helper.sent)")
        rig.helper.reply()
        precondition(rig.journal.journal != nil, "the journal stays dirty until the undo is acknowledged")
        rig.helper.reply()
        precondition(rig.journal.journal == nil, "the acknowledged undo cleans the journal")
        precondition(!rig.helper.isWaiting && rig.scheduler.delay == nil)
    }

    static func lidOldReplyKeepsNewJournal() {
        let defaults = suite()
        let old = holdingLid(defaults)
        old.switchOff()
        precondition(old.helper.sent.last == .batterySleepOn && old.helper.isWaiting)
        let fresh = Rig(switchingBackOn: old)
        precondition(fresh.helper.sent == [.batterySleepOn], "the new module replays the dirty journal")
        let freshEntry = fresh.journal.journal?.claim
        old.helper.reply()
        precondition(
            fresh.journal.journal?.claim == freshEntry && freshEntry != nil,
            "an old module's reply must not settle the new module's entry")
        fresh.helper.reply(.failed(1))
        advance(minutes: 1)
        fresh.scheduler.run()
        precondition(fresh.helper.sent == [.batterySleepOn, .batterySleepOn], "the new module still owns the retry")
        fresh.helper.reply()
        precondition(fresh.journal.journal == nil)
        precondition(old.scheduler.delay == nil, "the old module stops recovering once replaced")
    }

    static func lidStoppedModuleRetriesUndo() {
        let rig = holdingLid()
        rig.switchOff()
        for attempt in 1...3 {
            rig.helper.reply(.failed(1))
            precondition(rig.scheduler.delay != nil, "a stopped module's failed undo \(attempt) has a retry owner")
            advance(minutes: 60)
            rig.scheduler.run()
            precondition(rig.helper.sent.count == 2 + attempt && rig.helper.sent.last == .batterySleepOn)
        }
        rig.helper.reply()
        precondition(rig.journal.journal == nil && rig.scheduler.delay == nil, "recovery ends on acknowledgement")
    }

    static func lidRecoveryNeverGivesUp() {
        let defaults = suite()
        let rig = holdingLid(defaults)
        rig.module.toggle()
        var expected: [Duration] = []
        for attempt in 1...9 {
            rig.helper.reply(.failed(1))
            expected.append(.seconds(min(3600, 60 * 1 << (attempt - 1))))
            precondition(rig.scheduler.delay == expected.last, "attempt \(attempt): \(String(describing: rig.scheduler.delay))")
            advance(minutes: 60)
            rig.scheduler.run()
            precondition(rig.helper.sent.count == 2 + attempt, "failed undo \(attempt) is retried: \(rig.helper.sent.count)")
        }
        guard let stale = rig.helper.runningPID else { preconditionFailure("the crash leaves an undo running") }
        let relaunch = Rig(defaults, lidSwitch: true) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        precondition(relaunch.helper.sent == [.batterySleepOn], "a relaunch retries at once, its backoff reset")
        relaunch.helper.reply()
        precondition(relaunch.journal.journal != nil, "the crashed run's helper still runs, so it stays dirty")
        relaunch.helper.line.machine.exit(stale)
        precondition(relaunch.helper.sent == [.batterySleepOn, .batterySleepOn], "its exit re-sends the undo")
        relaunch.helper.reply()
        precondition(relaunch.journal.journal == nil)
    }

    static func lidEnableNeedsDurableJournal() {
        let rig = Rig(suite(), lidSwitch: true) { $0.journal.failWrites = true }
        rig.module.toggle()
        precondition(rig.held == held, "Keep Awake still holds")
        precondition(rig.helper.sent.isEmpty, "no disablesleep 1 without a durable journal: \(rig.helper.sent)")
        precondition(rig.presenter.notices.contains("Lid Setting Failed"))
        precondition(rig.scheduler.delay == .seconds(60), "the enable is retried later")
        rig.journal.failWrites = false
        advance(minutes: 1)
        rig.scheduler.run()
        precondition(rig.helper.sent == [.batterySleepOff] && rig.journal.journal != nil, "it enables once written")
        rig.helper.reply()
        rig.journal.failWrites = true
        rig.module.toggle()
        precondition(rig.helper.sent.last == .batterySleepOn, "a failing write never holds back disablesleep 0")
        rig.helper.reply()
    }

    static func lidObsoleteReplyNeverSleeps() {
        let defaults = suite()
        let old = holdingLid(defaults) { $0.lid.isClosed = true }
        old.switchOff()
        precondition(old.helper.sent.last == .batterySleepOn && old.helper.isWaiting)
        let fresh = Rig(switchingBackOn: old)
        old.helper.reply()
        precondition(old.lid.sleepRequests.isEmpty, "a replaced module's undo reply must not request sleep")
        fresh.helper.reply()

        let ended = holdingLid { $0.lid.isClosed = true }
        ended.module.toggle()
        ended.helper.reply()
        precondition(ended.lid.sleepRequests.count == 1 && ended.lid.sleepRequests[0]())
        ended.switchOff()
        precondition(ended.lid.sleepRequests[0](), "a switch-off with the lid shut still sleeps")
        let replaced = Rig(switchingBackOn: ended)
        precondition(!ended.lid.sleepRequests[0](), "a newer module withdraws the old sleep request")
        precondition(replaced.helper.sent.isEmpty)
    }

    static func lidDropsUnrunnableRetry() async {
        let rig = Rig(suite(), lidSwitch: true) {
            $0.set(KeepAwakeSettings.Key.minutes, 15)
            $0.journal.failWrites = true
        }
        rig.module.toggle()
        precondition(rig.helper.sent.isEmpty && rig.scheduler.delay == .seconds(60), "the enable waits to retry")
        rig.journal.failWrites = false
        rig.preferences.set(KeepAwakeModule.lidSwitchID, on: false)
        await Task.yield()
        advance(minutes: 2)
        rig.scheduler.run()
        precondition(
            rig.scheduler.delay == .seconds(13 * 60),
            "a retry nothing can run must not be scheduled: \(String(describing: rig.scheduler.delay))")
        precondition(rig.helper.sent.isEmpty)
        rig.preferences.set(KeepAwakeModule.lidSwitchID, on: true)
        await Task.yield()
        precondition(rig.helper.sent == [.batterySleepOff], "Lid Closed back on enables at once")
        rig.helper.reply()
    }
}
