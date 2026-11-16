// The recovery rig and crashed runs the recovery and scan harnesses share; never run on its own.
import Foundation

/// The add-on's recovery as the controller starts it: on its own context, before any module.
@MainActor
final class RecoveryRig {
    let assertions = FakeAssertions()
    let lid = FakeLid()
    let scheduler = FakeScheduler()
    let helper: FakeHelper
    let journal: FakeJournalStore
    let preferences: NotchcastPreferences
    let recovery: KeepAwakeRecovery

    init(
        _ defaults: UserDefaults, switchOn: Bool = false, helper: FakeHelper = FakeHelper(),
        processes: (any KeepAwakeProcesses)? = nil
    ) {
        self.helper = helper
        journal = FakeJournalStore(defaults)
        preferences = NotchcastPreferences(defaults: defaults, switches: Rig.switches)
        preferences.set(KeepAwakeModule.switchID, on: switchOn)
        let context = Rig.context(defaults, preferences, FakePresenter())
        recovery = KeepAwakeRecovery(
            context: context,
            system: KeepAwakeSystem(
                assertions: assertions, sensors: FakeSensors(), screenLock: FakeScreenLock(), lid: lid,
                helper: helper, processes: processes ?? helper.line.machine, sleepSetting: helper.line.machine,
                scheduler: scheduler, journal: journal))
        context.attach(recovery)
        recovery.start()
    }
}

extension KeepAwakeHarness {
    /// A suite whose journal says a crashed run left `disablesleep 1` set.
    static func dirty() -> UserDefaults {
        let defaults = suite()
        var journal = KeepAwakeSleepJournal()
        let operation = UUID()
        journal.begin(.batterySleepOff, operation: operation)
        journal.succeed(.batterySleepOff, operation: operation)
        precondition((try? FakeJournalStore(defaults).store(journal)) != nil)
        return defaults
    }

    static var machine: FakeProcesses { .shared }

    /// Run 1 sends `disablesleep 1`, the helper stalls and the app dies: that process is still alive.
    static func crashMidEnable(_ defaults: UserDefaults = suite()) -> (UserDefaults, Int32, Int32) {
        machine.sleepDisabled = false
        let crashed = Rig(defaults, lidSwitch: true)
        crashed.module.toggle()
        guard crashed.helper.sent == [.batterySleepOff], let pid = crashed.helper.runningPID,
            let child = crashed.helper.runningChild
        else { preconditionFailure("run 1 crashes with its disablesleep 1 unanswered") }
        return (defaults, pid, child)
    }

    /// Run 1 as above, on a Mac where sudo and the root helper it launched are separate processes.
    static func crashMidSplitEnable() -> (UserDefaults, sudo: Int32, helper: Int32) {
        machine.splitsSudo = true
        defer { machine.splitsSudo = false }
        let (defaults, sudo, helper) = crashMidEnable()
        precondition(sudo != helper && machine.isAlive(helper), "sudo's child is its own process")
        return (defaults, sudo, helper)
    }

    static func replyAll(_ helper: FakeHelper) {
        for _ in 0..<6 where helper.isWaiting { helper.reply() }
    }
}
