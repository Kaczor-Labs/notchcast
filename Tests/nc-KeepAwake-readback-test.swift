// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeHelperTracker.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeRecovery.swift
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
// notchcast-sources: Tests/nc-KeepAwake-recovery-fixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Foundation

/// An acknowledged undo settles only if the Mac's own setting then reads off.
@main
@MainActor
enum KeepAwakeReadbackTests: KeepAwakeHarness {
    static func main() {
        defer { removeSuites() }
        recoveryStaysDirtyWhenAChildAppliesAfterTheAck()
        moduleStaysDirtyWhenAChildAppliesAfterTheAck()
        relaunchRechecksTheSetting()
        recoveryStaysDirtyWhileTheSettingIsUnreadable()
        moduleSettlesAnUnreadableSettingForAWantingSession()
        print("nc-KeepAwake-readback-test: all checks passed")
    }

    /// A pre-exec child lands `disablesleep 1` and exits after the ack, so the scan finds nothing.
    static func childLandsAfterAck() {
        machine.beforeScan = {
            machine.land(.batterySleepOff)
            machine.beforeScan = nil
        }
    }

    static func recoveryStaysDirtyWhenAChildAppliesAfterTheAck() {
        machine.sleepDisabled = true
        childLandsAfterAck()
        let rig = RecoveryRig(dirty())
        rig.helper.reply()
        precondition(machine.sleepDisabled, "the child's verb landed after the undo")
        precondition(rig.journal.journal != nil, "the journal stays dirty while sleep reads disabled")
        precondition(rig.scheduler.delay != nil && !rig.helper.isWaiting, "and the undo retries on the backoff")
        advance(minutes: 2)
        rig.scheduler.run()
        rig.helper.reply()
        precondition(!machine.sleepDisabled && rig.journal.journal == nil, "the retry that reads off clears")
    }

    static func moduleStaysDirtyWhenAChildAppliesAfterTheAck() {
        machine.sleepDisabled = false
        let rig = Rig(suite(), lidSwitch: true)
        rig.module.toggle()
        rig.helper.reply()
        precondition(machine.sleepDisabled && rig.journal.journal != nil, "the session disabled sleep")
        childLandsAfterAck()
        rig.module.toggle()
        rig.helper.reply()
        precondition(machine.sleepDisabled, "the child's verb landed after the undo")
        precondition(rig.journal.journal != nil, "the journal stays dirty while sleep reads disabled")
        precondition(rig.scheduler.delay != nil, "and the undo retries")
        advance(minutes: 2)
        rig.scheduler.run()
        rig.helper.reply()
        precondition(!machine.sleepDisabled && rig.journal.journal == nil, "the retry that reads off clears")
    }

    /// A relaunch replays a dirty journal through the same read-back.
    static func relaunchRechecksTheSetting() {
        machine.sleepDisabled = true
        childLandsAfterAck()
        let defaults = dirty()
        let first = RecoveryRig(defaults)
        first.helper.reply()
        precondition(first.journal.journal != nil, "run 1 leaves the journal dirty")
        first.recovery.stop()
        childLandsAfterAck()
        let second = RecoveryRig(defaults)
        second.helper.reply()
        precondition(machine.sleepDisabled && second.journal.journal != nil, "run 2 re-checks and stays dirty")
        advance(minutes: 2)
        second.scheduler.run()
        second.helper.reply()
        precondition(!machine.sleepDisabled && second.journal.journal == nil, "and clears once it reads off")
    }

    static func recoveryStaysDirtyWhileTheSettingIsUnreadable() {
        machine.sleepDisabled = false
        machine.unreadableSleepSetting = true
        let rig = RecoveryRig(dirty())
        rig.helper.reply()
        precondition(rig.journal.journal != nil, "an unreadable setting with no session wanting it never clears")
        machine.unreadableSleepSetting = false
        advance(minutes: 2)
        rig.scheduler.run()
        rig.helper.reply()
        precondition(rig.journal.journal == nil, "a readable off setting clears")
    }

    /// A session that started while the undo was out wants sleep disabled, so an unreadable setting is no veto.
    static func moduleSettlesAnUnreadableSettingForAWantingSession() {
        machine.sleepDisabled = true
        let rig = Rig(dirty(), lidSwitch: true)
        precondition(rig.helper.sent == [.batterySleepOn], "the launch replays the undo")
        rig.module.toggle()
        machine.unreadableSleepSetting = true
        rig.helper.reply()
        machine.unreadableSleepSetting = false
        precondition(rig.helper.sent == [.batterySleepOn, .batterySleepOff], "the session's own verb follows the undo")
        rig.helper.reply()
        precondition(machine.sleepDisabled && rig.journal.journal != nil, "the session holds sleep disabled")
        rig.module.toggle()
        rig.helper.reply()
        precondition(!machine.sleepDisabled && rig.journal.journal == nil, "and its end undoes and clears")
    }
}
