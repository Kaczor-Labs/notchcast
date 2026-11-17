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
enum KeepAwakeTests: KeepAwakeHarness {
    static func main() {
        defer { removeSuites() }
        holdsOnlyWhileActive()
        endsOnTimer()
        locking()
        batteryFloor()
        relaunch()
        automation()
        print("nc-KeepAwake-test: all checks passed")
    }

    // MARK: - F108 Keep Awake

    static func holdsOnlyWhileActive() {
        let rig = Rig(suite())
        precondition(rig.held.isEmpty, "an idle module holds an assertion")
        precondition(rig.presenter.status == nil)
        rig.module.toggle()
        precondition(rig.held == held, "an active session must hold both idle assertions: \(rig.held)")
        precondition(rig.presenter.notices == ["Keep Awake On"])
        precondition(rig.presenter.status?.symbol == "cup.and.saucer.fill")
        rig.module.toggle()
        precondition(rig.held.isEmpty, "turning Keep Awake off must release every assertion")
        precondition(rig.module.session == nil && rig.presenter.status == nil)
        precondition(rig.presenter.notices.last == "Keep Awake Off")
        rig.module.toggle()
        rig.module.stop()
        precondition(rig.held.isEmpty, "quitting must release every assertion")
        precondition(rig.helper.sent.isEmpty, "Keep Awake alone must never call the root helper")
    }

    static func endsOnTimer() {
        let defaults = suite()
        defaults.set(15, forKey: KeepAwakeSettings.Key.minutes)
        let rig = Rig(defaults)
        rig.module.toggle()
        precondition(rig.scheduler.delay == .seconds(15 * 60), "the end time must be scheduled")
        advance(minutes: 15)
        rig.scheduler.run()
        precondition(rig.held.isEmpty && rig.module.session == nil, "a timed session must end on time")
        precondition(rig.presenter.notices.last == "Keep Awake Ended")
        precondition(defaults.data(forKey: KeepAwakeSettings.Key.session) == nil, "an ended session is not restorable")

        rig.module.extend()
        precondition(rig.held == held, "Extend on an idle module starts a session")
        let end = rig.module.session?.end
        rig.module.extend()
        precondition(rig.module.session?.end == end.map { $0 + 15 * 60 }, "Extend adds the chosen duration")
    }

    static func locking() {
        let paused = Rig(suite()) { $0.set(KeepAwakeSettings.Key.pausesWhenLocked, true) }
        paused.module.toggle()
        paused.screenLock.set(true)
        precondition(paused.held.isEmpty && paused.module.isPaused, "locking must release the assertions")
        precondition(paused.module.session != nil, "locking pauses the session; it does not end it")
        precondition(paused.presenter.status?.symbol == "cup.and.saucer")
        paused.screenLock.set(false)
        precondition(paused.held == held && !paused.module.isPaused, "unlocking must restore the assertions")

        let kept = Rig(suite())
        kept.module.toggle()
        kept.screenLock.set(true)
        precondition(kept.held == held, "locking must not pause unless the setting is on")
    }

    static func batteryFloor() {
        let rig = Rig(suite())
        rig.sensors.power = KeepAwakeBattery(onBattery: true, percent: 21)
        rig.module.toggle()
        precondition(rig.held == held, "21 % is above the default 20 % floor")
        precondition(rig.scheduler.delay == .seconds(KeepAwakeModule.batteryWatch), "on battery the floor is polled")
        rig.sensors.power.percent = 20
        rig.sensors.changed?()
        precondition(rig.held.isEmpty && rig.module.session == nil, "reaching the 20 % floor must end the session")
        precondition(rig.presenter.notices.last == "Battery Low")

        let never = Rig(suite()) { $0.set(KeepAwakeSettings.Key.floor, 0) }
        never.sensors.power = KeepAwakeBattery(onBattery: true, percent: 3)
        never.module.toggle()
        precondition(never.held == held, "a floor of Never keeps holding on battery")

        let top = Rig(suite()) { $0.set(KeepAwakeSettings.Key.floor, 50) }
        top.sensors.power = KeepAwakeBattery(onBattery: true, percent: 51)
        top.module.toggle()
        precondition(top.held == held)
        top.sensors.power.percent = 50
        top.sensors.changed?()
        precondition(top.module.session == nil, "the 50 % floor must end the session at 50 %")

        let policy = KeepAwakePolicy(enabled: true, floor: 80)
        precondition(policy.evaluate(now: Rig.clock, onBattery: true, percent: 51) == .hold, "the floor is capped at 50")
        precondition(policy.evaluate(now: Rig.clock, onBattery: true, percent: 50) == .batteryFloor)
        precondition(policy.evaluate(now: Rig.clock, onBattery: true, percent: nil) == .batteryFloor)
        precondition(policy.evaluate(now: Rig.clock, onBattery: false, percent: 5) == .hold)
    }

    static func relaunch() {
        let quit = suite()
        let first = Rig(quit)
        first.module.toggle()
        let end = first.module.session?.end
        first.module.stop()
        advance(minutes: 10)
        let second = Rig(quit)
        precondition(second.held == held, "a session must survive a quit and relaunch")
        precondition(second.module.session?.end == end, "a restored session keeps its end time")
        precondition(second.presenter.notices.isEmpty, "a restore is silent")

        let crash = suite()
        Rig(crash).module.toggle()
        advance(minutes: 1)
        precondition(Rig(crash).held == held, "a session a crash left dirty must replay on the next launch")

        let expired = suite()
        Rig(expired).module.toggle()
        advance(minutes: 61)
        let late = Rig(expired)
        precondition(late.held.isEmpty, "an expired session must not come back")
        precondition(expired.data(forKey: KeepAwakeSettings.Key.session) == nil)

        let off = suite()
        Rig(off).module.toggle()
        let opted = Rig(off) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        precondition(opted.held.isEmpty, "turning restore off must start the next launch idle")

        let switchedOff = suite()
        let rig = Rig(switchedOff)
        rig.module.toggle()
        rig.preferences.set(KeepAwakeModule.switchID, on: false)
        rig.module.stop()
        rig.preferences.set(KeepAwakeModule.switchID, on: true)
        precondition(Rig(switchedOff).held.isEmpty, "turning the switch off ends the session for good")
    }

    static func automation() {
        let rig = Rig(suite()) { $0.set(KeepAwakeSettings.Key.autoPower, true) }
        precondition(rig.held.isEmpty)
        rig.sensors.facts.onPower = true
        rig.sensors.changed?()
        precondition(rig.held == held && rig.module.session?.isAutomatic == true, "plugging in starts a session")
        precondition(rig.presenter.notices.isEmpty, "an automatic start is silent")
        rig.module.toggle()
        precondition(rig.held.isEmpty, "the person can turn an automatic session off")
        rig.sensors.changed?()
        precondition(rig.held.isEmpty, "a suppressed automation stays off while its conditions hold")
        rig.sensors.facts.onPower = false
        rig.sensors.changed?()
        rig.sensors.facts.onPower = true
        rig.sensors.changed?()
        precondition(rig.held == held, "the suppression lapses once the conditions do")
        rig.sensors.facts.onPower = false
        rig.sensors.changed?()
        precondition(rig.held.isEmpty, "unplugging ends an automatic session")
    }
}
