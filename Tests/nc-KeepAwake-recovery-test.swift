// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeHelperTracker.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeRecovery.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap*.swift
// notchcast-sources: Tests/nc-KeepAwake-fixtures.swift
// notchcast-sources: Tests/nc-KeepAwake-machine.swift
// notchcast-sources: Tests/nc-KeepAwake-recovery-fixtures.swift
import Foundation

@main
@MainActor
enum KeepAwakeRecoveryTests: KeepAwakeHarness {
    static func main() async {
        defer { removeSuites() }
        recoveryUndoesDirtyJournalWithSwitchOff()
        recoveryLeavesCleanJournal()
        recoveryDefersToModuleAtLaunch()
        recoveryYieldsToLaterModule()
        recoveryRetriesUntilAcknowledged()
        recoveryRequestsLidSleep()
        recoveryOutlastsStalledEnable()
        recoveryRedoesUndoInFlightAtExit()
        recoveryKeepsUnwatchableHelperDirty()
        await recoveryRedoesUndoForGoneHelper()
        recoveryHandsStaleHelperToModule()
        recoveryReadsOldJournalAsUnreadable()
        print("nc-KeepAwake-recovery-test: all checks passed")
    }

    static func recoveryUndoesDirtyJournalWithSwitchOff() {
        let rig = RecoveryRig(dirty())
        precondition(rig.helper.sent == [.batterySleepOn], "a dirty journal is undone with the switch off: \(rig.helper.sent)")
        rig.recovery.start()
        precondition(rig.helper.sent.count == 1, "the recovery runs once")
        precondition(rig.journal.journal != nil, "the journal stays dirty until the helper acknowledges")
        precondition(rig.assertions.live.isEmpty, "the recovery never holds an assertion")
        rig.helper.reply()
        precondition(rig.journal.journal == nil, "the acknowledged undo clears the journal")
        precondition(!rig.helper.isWaiting && rig.scheduler.delay == nil && rig.lid.sleepRequests.isEmpty)

        let unreadable = suite()
        unreadable.set(Data("not a journal".utf8), forKey: FakeJournalStore.key)
        let garbled = RecoveryRig(unreadable)
        precondition(garbled.helper.sent == [.batterySleepOn], "an unreadable journal is still undone")
        garbled.helper.reply(.unsupported)
        precondition(garbled.journal.journal == nil && garbled.scheduler.delay == nil, "a helper without the verb ends it")
    }

    static func recoveryLeavesCleanJournal() {
        let rig = RecoveryRig(suite())
        rig.recovery.stop()
        precondition(rig.helper.sent.isEmpty && rig.scheduler.delay == nil, "a clean journal needs no helper call")
    }

    static func recoveryDefersToModuleAtLaunch() {
        var recovery: RecoveryRig?
        let rig = Rig(dirty()) { recovery = RecoveryRig($0.defaults, switchOn: true, helper: $0.helper) }
        precondition(rig.helper.sent == [.batterySleepOn], "with the switch on only the module undoes: \(rig.helper.sent)")
        rig.helper.reply()
        precondition(rig.journal.journal == nil && recovery?.scheduler.delay == nil)

        let kept = suite()
        let crashed = Rig(kept, lidSwitch: true)
        crashed.module.toggle()
        crashed.helper.reply()
        let relaunch = Rig(kept, lidSwitch: true) { recovery = RecoveryRig($0.defaults, switchOn: true, helper: $0.helper) }
        precondition(relaunch.held == held && relaunch.helper.sent.isEmpty, "a restored session keeps disablesleep 1")
    }

    static func recoveryYieldsToLaterModule() {
        for reply in [KeepAwakeHelperResult.ok, .failed(1)] {
            let defaults = dirty()
            let recovery = RecoveryRig(defaults)
            let module = Rig(defaults, helper: FakeHelper(line: recovery.helper.line))
            precondition(module.helper.sent == [.batterySleepOn], "a module turned on mid-recovery takes the undo over")
            let entry = module.journal.journal?.claim
            recovery.helper.reply(reply)
            precondition(
                module.journal.journal?.claim == entry && entry != nil, "the recovery's late \(reply) keeps the module's entry")
            precondition(recovery.scheduler.delay == nil, "the recovery stops once the module owns the undo")
            module.helper.reply()
            precondition(module.journal.journal == nil)
        }
    }

    static func recoveryRetriesUntilAcknowledged() {
        let rig = RecoveryRig(dirty())
        rig.helper.reply(.failed(1))
        precondition(rig.scheduler.delay == .seconds(60), "a failed undo retries after a minute")
        for attempt in 1...3 {
            advance(minutes: 60)
            rig.scheduler.run()
            precondition(rig.helper.sent.count == 1 + attempt, "retry \(attempt) sends the undo again")
            rig.helper.reply(attempt == 3 ? .ok : .failed(1))
        }
        precondition(rig.journal.journal == nil && rig.scheduler.delay == nil, "the retries end on acknowledgement")

        let quitting = RecoveryRig(dirty())
        quitting.helper.reply(.failed(1))
        quitting.recovery.stop()
        precondition(quitting.scheduler.delay == nil, "core stop ends the retries")

        let late = RecoveryRig(dirty())
        late.recovery.stop()
        late.helper.reply()
        precondition(late.journal.journal == nil, "an undo sent before core stop still clears on acknowledgement")
    }

    static func recoveryRequestsLidSleep() {
        let rig = RecoveryRig(dirty())
        rig.lid.isClosed = true
        rig.helper.reply()
        precondition(rig.lid.sleepRequests.count == 1 && rig.lid.sleepRequests[0](), "a closed lid sleeps after the undo")
        rig.preferences.set(KeepAwakeModule.switchID, on: true)
        precondition(!rig.lid.sleepRequests[0](), "Keep Awake turning on withdraws the sleep request")

        let failed = RecoveryRig(dirty())
        failed.lid.isClosed = true
        failed.helper.reply(.failed(1))
        precondition(failed.lid.sleepRequests.isEmpty, "no sleep while disablesleep 1 may still be set")
    }

    // MARK: - A stalled helper outliving its run

    static func recoveryOutlastsStalledEnable() {
        let (defaults, stale, _) = crashMidEnable()
        let rig = RecoveryRig(defaults)
        precondition(rig.helper.sent == [.batterySleepOn], "the relaunch undoes at once")
        rig.helper.reply()
        precondition(!machine.sleepDisabled, "the relaunch undo lands")
        precondition(rig.journal.journal != nil, "the earlier run's helper still runs, so the journal stays dirty")
        machine.land(.batterySleepOff)
        precondition(machine.sleepDisabled, "the stalled enable lands late")
        machine.exit(stale)
        precondition(rig.helper.sent == [.batterySleepOn, .batterySleepOn], "its exit re-sends the undo")
        precondition(rig.journal.journal != nil, "and the journal waits for that ack")
        rig.helper.reply()
        precondition(!machine.sleepDisabled, "the late disablesleep 1 is undone: \(machine.sleepDisabled)")
        precondition(rig.journal.journal == nil && rig.scheduler.delay == nil, "the acknowledged re-undo cleans it")
        precondition(!machine.isAlive(stale) && machine.watching == 0, "no watch outlives the recovery")
    }

    static func recoveryRedoesUndoInFlightAtExit() {
        let (defaults, stale, _) = crashMidEnable()
        let rig = RecoveryRig(defaults)
        machine.land(.batterySleepOff)
        machine.exit(stale)
        precondition(rig.helper.sent == [.batterySleepOn], "an undo already out is not doubled")
        rig.helper.reply()
        precondition(rig.journal.journal != nil, "an undo out across the exit may have landed first: no clear")
        precondition(rig.helper.sent == [.batterySleepOn, .batterySleepOn], "so it is sent again")
        rig.helper.reply()
        precondition(rig.journal.journal == nil && !machine.sleepDisabled)
    }

    static func recoveryKeepsUnwatchableHelperDirty() {
        let (defaults, stale, _) = crashMidEnable()
        machine.unwatchable = true
        defer { machine.unwatchable = false }
        let rig = RecoveryRig(defaults)
        rig.helper.reply()
        machine.land(.batterySleepOff)
        machine.exit(stale)
        precondition(rig.helper.sent == [.batterySleepOn], "an exit nobody could watch sends nothing")
        precondition(rig.journal.journal != nil, "an unwatchable helper leaves the journal dirty for the next launch")
        precondition(!rig.helper.isWaiting && rig.scheduler.delay == nil)
    }

    static func recoveryRedoesUndoForGoneHelper() async {
        let (defaults, stale, _) = crashMidEnable()
        machine.unwatchable = true
        _ = RecoveryRig(defaults).helper.reply()
        machine.unwatchable = false
        machine.land(.batterySleepOff)
        machine.exit(stale)
        let next = RecoveryRig(defaults)
        precondition(next.helper.sent == [.batterySleepOn], "the next launch retries")
        next.helper.reply()
        await settle { next.helper.sent.count == 2 }
        precondition(next.helper.sent == [.batterySleepOn, .batterySleepOn], "a helper already gone re-sends the undo")
        next.helper.reply()
        precondition(next.journal.journal == nil && !machine.sleepDisabled, "then the journal clears")

        let (reusedDefaults, reused, _) = crashMidEnable()
        machine.exit(reused)
        _ = machine.spawn(pid: reused)
        let after = RecoveryRig(reusedDefaults)
        after.helper.reply()
        await settle { after.helper.sent.count == 2 }
        precondition(after.helper.sent == [.batterySleepOn, .batterySleepOn], "a reused pid is not the stalled helper")
        after.helper.reply()
        precondition(after.journal.journal == nil, "so it is undone once more and cleared")
        machine.exit(reused)
    }

    static func recoveryHandsStaleHelperToModule() {
        let (defaults, stale, _) = crashMidEnable()
        let recovery = RecoveryRig(defaults)
        let module = Rig(defaults, lidSwitch: true, helper: FakeHelper(line: recovery.helper.line)) {
            $0.set(KeepAwakeSettings.Key.restoresSession, false)
        }
        recovery.helper.reply()
        machine.land(.batterySleepOff)
        machine.exit(stale)
        for _ in 0..<6 where module.helper.isWaiting { module.helper.reply() }
        precondition(recovery.helper.sent == [.batterySleepOn], "the recovery stands down once the module owns it")
        precondition(module.journal.journal == nil && !machine.sleepDisabled, "the module re-undoes the late enable")
        precondition(module.helper.sent.allSatisfy { $0 == .batterySleepOn } && module.helper.sent.count >= 2)
        precondition(machine.watching == 0)
    }

    /// The journal as the previous release wrote it, before helper processes were recorded.
    struct OldJournal: Codable {
        struct Effect: Codable {
            var applied: KeepAwakeSleepVerb?
            var intent: KeepAwakeSleepVerb?
            var operation: UUID?
        }
        var effect: Effect?
    }

    static func recoveryReadsOldJournalAsUnreadable() {
        let defaults = suite()
        let old = OldJournal(effect: .init(applied: .batterySleepOff, intent: nil, operation: UUID()))
        guard let data = try? JSONEncoder().encode(old) else { preconditionFailure("the old journal encodes") }
        defaults.set(data, forKey: FakeJournalStore.key)
        precondition(FakeJournalStore(defaults).journal == nil, "a journal without helpers does not decode")
        let rig = RecoveryRig(defaults)
        precondition(rig.helper.sent == [.batterySleepOn], "a journal from before helpers were recorded is still undone")
        rig.helper.reply()
        precondition(rig.journal.journal == nil)
    }
}
