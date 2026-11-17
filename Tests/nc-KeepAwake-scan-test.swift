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
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeLiveProcesses.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeRootClient.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Darwin
import Foundation

/// Older processes that may still land a verb sent before the undo: none may let the journal clear.
@main
@MainActor
enum KeepAwakeScanTests: KeepAwakeHarness {
    static func main() async {
        defer { removeSuites() }
        recoveryWaitsForHelperSudoLeftBehind()
        recoveryClearsWhenSudoOutlivesHelper()
        recoveryStaysDirtyWhenScanFails()
        await recoveryTreatsReusedHelperPIDAsExited()
        moduleWaitsForHelperSudoLeftBehind()
        recoveryWaitsForPreExecChild()
        await recoveryStaysDirtyOnUnreadableProcess()
        await recoveryStaysDirtyWhenAParentVanishesMidScan()
        await recoveryStaysDirtyWhenEveryPassVanishes()
        print("nc-KeepAwake-scan-test: all checks passed")
    }

    static func recoveryWaitsForHelperSudoLeftBehind() {
        let (defaults, sudo, child) = crashMidSplitEnable()
        let rig = RecoveryRig(defaults)
        machine.exit(sudo)
        replyAll(rig.helper)
        precondition(!machine.sleepDisabled, "the relaunch undo lands")
        precondition(rig.journal.journal != nil, "sudo is gone but its root helper runs: the journal stays dirty")
        precondition(machine.watching == 1, "the root helper itself is watched")
        let sent = rig.helper.sent.count
        machine.land(.batterySleepOff)
        machine.exit(child)
        precondition(rig.helper.sent.count == sent + 1, "the helper's exit re-sends the undo")
        precondition(rig.journal.journal != nil, "and the journal waits for that ack")
        rig.helper.reply()
        precondition(!machine.sleepDisabled, "the late disablesleep 1 is undone")
        precondition(rig.journal.journal == nil && machine.watching == 0, "then the journal clears")
    }

    static func recoveryClearsWhenSudoOutlivesHelper() {
        let (defaults, sudo, child) = crashMidSplitEnable()
        let rig = RecoveryRig(defaults)
        machine.exit(child)
        rig.helper.reply()
        precondition(rig.journal.journal != nil, "sudo still runs, so the journal stays dirty")
        machine.exit(sudo)
        replyAll(rig.helper)
        precondition(rig.journal.journal == nil && !machine.sleepDisabled, "its exit re-undoes, and the ack clears")
        precondition(machine.watching == 0)
    }

    static func recoveryStaysDirtyWhenScanFails() {
        let (defaults, sudo, child) = crashMidSplitEnable()
        machine.unscannable = true
        let rig = RecoveryRig(defaults)
        machine.exit(child)
        machine.exit(sudo)
        replyAll(rig.helper)
        precondition(rig.journal.journal != nil, "an ack nobody could check for older helpers never clears")
        precondition(rig.scheduler.delay != nil && !rig.helper.isWaiting, "it retries on the backoff")
        machine.unscannable = false
        rig.scheduler.run()
        replyAll(rig.helper)
        precondition(rig.journal.journal == nil, "a retry that can scan clears")
    }

    static func recoveryTreatsReusedHelperPIDAsExited() async {
        let (defaults, sudo, child) = crashMidSplitEnable()
        let second = RecoveryRig(defaults)
        machine.exit(sudo)
        replyAll(second.helper)
        precondition(second.journal.journal?.effect?.helpers.map(\.pid) == [child], "the root helper is journalled")
        second.recovery.stop()
        machine.exit(child)
        _ = machine.spawn(pid: child)
        let third = RecoveryRig(defaults)
        replyAll(third.helper)
        await settle { third.helper.isWaiting }
        replyAll(third.helper)
        precondition(third.helper.sent.count == 2, "a reused pid is not the root helper: it is undone again")
        precondition(third.journal.journal == nil && machine.watching == 0, "and cleared")
        machine.exit(child)
    }

    static func moduleWaitsForHelperSudoLeftBehind() {
        let (defaults, sudo, child) = crashMidSplitEnable()
        let rig = Rig(defaults, lidSwitch: true) { $0.set(KeepAwakeSettings.Key.restoresSession, false) }
        machine.exit(sudo)
        replyAll(rig.helper)
        precondition(rig.journal.journal != nil, "the module waits for the root helper too")
        machine.land(.batterySleepOff)
        machine.exit(child)
        replyAll(rig.helper)
        precondition(rig.journal.journal == nil && !machine.sleepDisabled, "its exit re-undoes, and the ack clears")
        precondition(machine.watching == 0)
    }

    /// An old sudo forks after the undo started and dies before its child execs: the child still lands.
    static func recoveryWaitsForPreExecChild() {
        for (old, late) in [(KeepAwakeStrays.sudo, KeepAwakeStrays.sudo), (FakeProcesses.helperPath, KeepAwakeStrays.pmset)] {
            machine.sleepDisabled = true
            let app = machine.spawn("/old/app", parent: 1)
            let parent = machine.spawn(old, parent: app)
            machine.exit(app)
            let rig = RecoveryRig(dirty())
            let child = machine.spawn(late, parent: parent)
            machine.exit(parent)
            rig.helper.reply()
            precondition(!machine.sleepDisabled, "the undo lands")
            precondition(rig.journal.journal != nil, "a \(late) child of an older \(old) keeps the journal dirty")
            precondition(machine.watching == 1, "and is watched")
            if late == KeepAwakeStrays.sudo { machine.exec(child) }
            machine.land(.batterySleepOff)
            machine.exit(child)
            replyAll(rig.helper)
            precondition(!machine.sleepDisabled, "its late disablesleep 1 is undone")
            precondition(rig.journal.journal == nil && machine.watching == 0, "then the journal clears")
        }
    }

    /// The real scan over a scripted lookup: only a zombie or an unrelated process may be left out.
    static func recoveryStaysDirtyOnUnreadableProcess() async {
        let pid: Int32 = 4242
        let alive = KeepAwakeProcessLookup.Info(id: .init(pid: pid, started: 1), parent: 1, zombie: false)
        let denied = KeepAwakeProcessLookup.Unreadable(code: EPERM)
        let cases: [(String, KeepAwakeProcessLookup, clears: Bool)] = [
            ("an unreadable path", .init(pids: { [pid] }, info: { _ in alive }, path: { _ in throw denied }), false),
            ("an unreadable sysctl", .init(pids: { [pid] }, info: { _ in throw denied }, path: { _ in "" }), false),
            ("a path read as gone", .init(pids: { [pid] }, info: { _ in alive }, path: { _ in nil }), false),
            ("an unlistable table", .init(pids: { throw denied }, info: { _ in nil }, path: { _ in nil }), false),
            ("a process gone before it is read", .init(pids: { [pid] }, info: { _ in nil }, path: { _ in nil }), false),
            ("an unrelated process", .init(pids: { [pid] }, info: { _ in alive }, path: { _ in "/bin/ls" }), true),
        ]
        for (name, lookup, clears) in cases {
            let processes = KeepAwakeLiveProcesses(helperPath: FakeProcesses.helperPath, lookup: lookup)
            let rig = RecoveryRig(dirty(), processes: processes)
            rig.helper.reply()
            for _ in 0..<200 where rig.journal.journal != nil && rig.scheduler.delay == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            precondition((rig.journal.journal == nil) == clears, "\(name): the journal clears only if \(clears)")
            precondition((rig.scheduler.delay != nil) != clears, "\(name): an unchecked ack retries on the backoff")
            rig.recovery.stop()
        }
    }

    /// Counts the scripted lookup's reads from the scan's off-main thread.
    final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { count += 1; return count } }
        var value: Int { lock.withLock { count } }
    }

    /// The live scan over a scripted lookup; its exits are the test's, never a real pid's on this Mac.
    @MainActor
    final class ScriptedScan: KeepAwakeProcesses {
        private let live: KeepAwakeLiveProcesses
        private var watches: [FakeWatch] = []
        private let (scans, scan) = AsyncStream<Void>.makeStream()

        init(helperPath: String, lookup: KeepAwakeProcessLookup) {
            live = KeepAwakeLiveProcesses(helperPath: helperPath, lookup: lookup)
        }

        func identify(_ pid: Int32) -> KeepAwakeHelperID? { live.identify(pid) }

        func watch(
            _ helper: KeepAwakeHelperID, exited: @escaping @MainActor @Sendable () -> Void
        ) -> (any KeepAwakeProcessWatch)? {
            let watch = FakeWatch(helper, exited)
            watches.append(watch)
            return watch
        }

        func strays(olderThan undo: Int64, _ found: @escaping @MainActor @Sendable ([KeepAwakeHelperID]?) -> Void) {
            live.strays(olderThan: undo) { [scan] strays in
                found(strays)
                scan.yield()
            }
        }

        /// Returns once a scan's result, and everything it ran synchronously, has landed.
        func scanned() async {
            for await _ in scans { return }
        }

        func exit(_ pid: Int32) {
            precondition(watches.contains { $0.helper.pid == pid && $0.isArmed }, "pid \(pid) is watched")
            watches.filter { $0.helper.pid == pid }.forEach { $0.fire() }
        }
    }

    /// An old helper descendant forks after the table is listed, then vanishes before it is read:
    /// the next pass must list the orphaned child, or its late disablesleep 1 outlives the journal.
    static func recoveryStaysDirtyWhenAParentVanishesMidScan() async {
        let (parent, child): (Int32, Int32) = (4343, 4344)
        let old = KeepAwakeProcessLookup.Info(id: .init(pid: parent, started: 1), parent: 1, zombie: false)
        let orphan = KeepAwakeProcessLookup.Info(id: .init(pid: child, started: 9), parent: 1, zombie: false)
        let helperPath = FakeProcesses.helperPath
        for vanishesAt in [1, 2] {
            machine.sleepDisabled = true
            let (lists, infos) = (Reads(), Reads())
            let lookup = KeepAwakeProcessLookup(
                pids: { lists.next() == 1 ? [parent] : [child] },
                info: { pid in
                    if pid == child { return orphan }
                    guard pid == parent else { return nil }
                    return lists.value == 1 && infos.next() == vanishesAt ? nil : old
                },
                path: { $0 == child ? KeepAwakeStrays.sudo : helperPath })
            let processes = ScriptedScan(helperPath: helperPath, lookup: lookup)
            let rig = RecoveryRig(dirty(), processes: processes)
            rig.helper.reply()
            await processes.scanned()
            precondition(!machine.sleepDisabled, "the undo landed and the setting reads off")
            precondition(
                rig.journal.journal != nil && rig.helper.sent.count == 1,
                "read \(vanishesAt): the orphaned child is found, so the journal stays dirty")
            processes.exit(child)
            precondition(rig.helper.sent.count == 2, "read \(vanishesAt): the orphan's exit runs the undo again")
            machine.land(.batterySleepOff)
            for _ in 0..<20 { await Task.yield() }
            precondition(rig.journal.journal != nil, "its late disablesleep 1 finds the journal dirty")
            rig.recovery.stop()
        }
    }

    /// Every pass losing a process is a scan nobody can trust: it fails and the undo retries.
    static func recoveryStaysDirtyWhenEveryPassVanishes() async {
        let alive = KeepAwakeProcessLookup.Info(id: .init(pid: 4545, started: 1), parent: 1, zombie: false)
        let reads = Reads()
        let lookup = KeepAwakeProcessLookup(
            pids: { [4545] }, info: { _ in reads.next() % 2 == 1 ? alive : nil }, path: { _ in "" })
        let processes = KeepAwakeLiveProcesses(helperPath: FakeProcesses.helperPath, lookup: lookup)
        let rig = RecoveryRig(dirty(), processes: processes)
        rig.helper.reply()
        for _ in 0..<200 where rig.scheduler.delay == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(rig.journal.journal != nil && rig.scheduler.delay != nil, "five lossy passes fail the scan")
        rig.recovery.stop()
    }
}
