// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeHelperTracker.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeLiveProcesses.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap*.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeRootClient.swift
// notchcast-sources: Tinycast/Features/Notchcast/KeepAwake/Service/KeepAwakeFileJournalStore.swift
// notchcast-sources: Tests/nc-KeepAwake-fixtures.swift
// notchcast-sources: Tests/nc-KeepAwake-machine.swift
import Foundation

@MainActor
final class FakeProcess: KeepAwakeHelperProcess {
    let processIdentifier: Int32
    var terminated = 0
    init(_ pid: Int32) { processIdentifier = pid }
    func terminate() { terminated += 1 }
}

/// Stands in for `sudo`: records each launch and lets the check decide when the process exits.
@MainActor
final class FakeLauncher {
    struct LaunchFailed: Error {}

    var verbs: [KeepAwakeSleepVerb] = []
    var exits: [KeepAwakeHelperLine.Exit] = []
    var processes: [FakeProcess] = []
    var failNext = false

    func launch(_ verb: KeepAwakeSleepVerb, exited: @escaping KeepAwakeHelperLine.Exit) throws -> any KeepAwakeHelperProcess {
        if failNext {
            failNext = false
            throw LaunchFailed()
        }
        verbs.append(verb)
        exits.append(exited)
        processes.append(FakeProcess(Int32(500 + processes.count)))
        return processes[processes.count - 1]
    }
}

@MainActor
final class LineRig {
    let launcher = FakeLauncher()
    let timer = FakeScheduler()
    var replies: [KeepAwakeHelperResult] = []
    var launched: [Int32] = []
    lazy var line = KeepAwakeHelperLine(timeout: .seconds(12), timer: timer, launch: launcher.launch)

    func send(_ verb: KeepAwakeSleepVerb) {
        line.send(verb) { [self] in launched.append($0) } done: { [self] in replies.append($0) }
    }

    /// Exits arrive on a background queue in the app, so this one comes from off the main actor too.
    func exit(_ index: Int, _ result: KeepAwakeHelperResult = .ok) async {
        let exited = launcher.exits[index]
        await Task.detached { exited(result) }.value
    }
}

@MainActor
final class Fired {
    var count = 0
}

@main
@MainActor
enum KeepAwakeTransportTests: KeepAwakeHarness {
    static func main() async {
        await lineRunsOneCallAtATime()
        await lineTimeoutNeverAdvances()
        await lineSendNeverBlocks()
        await lineLaunchFailureMovesOn()
        await lineIgnoresStaleExits()
        await lineReportsEachLaunch()
        await liveProcessesWatchExit()
        resultMapping()
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-keepawake-store.\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try storeEstablishesNewFolders(root.appending(path: "durable"))
            try storeRetriesAFailedSync(root.appending(path: "retry"))
            try storeKeepsRecordWhenWriteFails(root.appending(path: "readonly"))
            try storeRefusesOutsideRoot(root)
            try storeLoadAndRemove(root.appending(path: "load"))
        } catch {
            preconditionFailure("a journal store check threw: \(error)")
        }
        print("nc-KeepAwake-transport-test: all checks passed")
    }

    // MARK: - Helper line

    static func lineRunsOneCallAtATime() async {
        let rig = LineRig()
        rig.send(.batterySleepOff)
        precondition(rig.launcher.verbs == [.batterySleepOff], "an idle line launches before send returns")
        precondition(rig.timer.delay == .seconds(12), "every launch arms the timeout")
        rig.send(.batterySleepOn)
        precondition(rig.launcher.verbs == [.batterySleepOff], "a second call waits for the first to exit")
        await rig.exit(0)
        await settle { rig.launcher.verbs.count == 2 }
        precondition(rig.replies == [.ok], "the first call's reply lands once it exits")
        precondition(rig.launcher.verbs == [.batterySleepOff, .batterySleepOn], "then the next call starts")
        precondition(rig.timer.delay == .seconds(12))
        await rig.exit(1, .failed(3))
        await settle { rig.replies.count == 2 }
        precondition(rig.replies == [.ok, .failed(3)] && rig.timer.delay == nil, "an idle line arms nothing")
    }

    static func lineTimeoutNeverAdvances() async {
        let rig = LineRig()
        rig.send(.batterySleepOff)
        rig.send(.batterySleepOn)
        rig.timer.run()
        precondition(rig.launcher.processes[0].terminated == 1, "a call past its timeout is terminated")
        for _ in 0..<20 { await Task.yield() }
        precondition(
            rig.launcher.verbs == [.batterySleepOff] && rig.replies.isEmpty,
            "a timed-out call that has not exited must hold the line: \(rig.launcher.verbs)")
        await rig.exit(0, .failed(-15))
        await settle { rig.launcher.verbs.count == 2 }
        precondition(rig.replies == [.failed(-15)], "the terminated call replies with its real exit")
        precondition(rig.launcher.verbs == [.batterySleepOff, .batterySleepOn], "only its exit frees the line")
    }

    static func lineSendNeverBlocks() async {
        let rig = LineRig()
        rig.send(.batterySleepOff)
        let started = ContinuousClock.now
        rig.send(.batterySleepOn)
        let took = ContinuousClock.now - started
        precondition(took < .milliseconds(100), "send must never wait on main for a running call: \(took)")
        await rig.exit(0)
        await settle { rig.launcher.verbs.count == 2 }
        await rig.exit(1)
    }

    static func lineLaunchFailureMovesOn() async {
        let rig = LineRig()
        rig.launcher.failNext = true
        rig.send(.batterySleepOff)
        precondition(rig.replies.isEmpty, "a failed launch replies later, never inside send")
        await settle { !rig.replies.isEmpty }
        precondition(rig.replies == [.failed(-1)] && rig.timer.delay == nil)

        rig.send(.batterySleepOff)
        rig.send(.batterySleepOn)
        rig.send(.batterySleepOff)
        rig.launcher.failNext = true
        await rig.exit(0)
        await settle { rig.replies.count == 3 && rig.launcher.verbs.count == 2 }
        precondition(rig.replies == [.failed(-1), .ok, .failed(-1)], "a launch that fails is answered")
        precondition(rig.launcher.verbs == [.batterySleepOff, .batterySleepOff], "and the line moves on")
    }

    static func lineIgnoresStaleExits() async {
        let rig = LineRig()
        rig.send(.batterySleepOff)
        rig.send(.batterySleepOn)
        await rig.exit(0)
        await rig.exit(0, .failed(9))
        await settle { rig.launcher.verbs.count == 2 }
        for _ in 0..<20 { await Task.yield() }
        precondition(rig.replies == [.ok], "a second exit of an old call is ignored: \(rig.replies)")
        precondition(rig.timer.delay == .seconds(12), "and leaves the running call's timeout armed")
        await rig.exit(1)
        await settle { rig.replies.count == 2 }
        precondition(rig.replies == [.ok, .ok])
    }

    static func lineReportsEachLaunch() async {
        let rig = LineRig()
        rig.send(.batterySleepOff)
        precondition(rig.launched == [500], "a launch is reported before send returns, with its pid")
        precondition(rig.line.isRunning(500) && !rig.line.isRunning(501))
        rig.send(.batterySleepOn)
        precondition(rig.launched == [500], "a waiting call has no process yet")
        await rig.exit(0)
        await settle { rig.launched.count == 2 }
        precondition(rig.launched == [500, 501] && !rig.line.isRunning(500) && rig.line.isRunning(501))
        await rig.exit(1)
        await settle { rig.replies.count == 2 }
        precondition(!rig.line.isRunning(501), "an idle line runs nothing")
        rig.launcher.failNext = true
        rig.send(.batterySleepOff)
        await settle { rig.replies.count == 3 }
        precondition(rig.launched == [500, 501], "a launch that failed started no process")
    }

    /// A harmless `sleep` child stands in for the helper: the real source must fire when it exits.
    static func liveProcessesWatchExit() async {
        let processes = KeepAwakeLiveProcesses(helperPath: "/bin/sleep")
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["0.3"]
        do { try child.run() } catch { preconditionFailure("could not start sleep: \(error)") }
        let pid = child.processIdentifier
        guard let helper = processes.identify(pid) else { preconditionFailure("a live pid has an identity") }
        precondition(processes.identify(pid) == helper, "the identity is stable while it runs")
        let found = await scan(processes), cat = await scan(KeepAwakeLiveProcesses(helperPath: "/bin/cat"))
        precondition(found?.contains(helper) == true, "the scan finds it by executable path")
        precondition(cat?.contains(helper) == false)
        let fired = Fired()
        let watch = processes.watch(helper) { fired.count += 1 }
        precondition(watch != nil && fired.count == 0, "a running process is watched, not reported gone")
        await waitReal { fired.count == 1 }
        child.waitUntilExit()
        for _ in 0..<20 { await Task.yield() }
        precondition(fired.count == 1, "the exit fires once")
        precondition(processes.identify(pid) == nil, "a reaped pid has no identity")
        let after = await scan(processes)
        precondition(after?.contains(helper) == false, "nor does the scan list it")

        let reused = Fired()
        let other = KeepAwakeHelperID(pid: ProcessInfo.processInfo.processIdentifier, started: 1)
        let stillUp = processes.watch(other) { reused.count += 1 }
        await settle { reused.count == 1 }
        precondition(stillUp != nil, "a live pid with another start is a different process: it fires")

        let gone = Fired()
        _ = processes.watch(helper) { gone.count += 1 }
        await settle { gone.count == 1 }

        let cancelled = Fired()
        let mine = processes.identify(ProcessInfo.processInfo.processIdentifier)!
        processes.watch(mine) { cancelled.count += 1 }?.cancel()
        for _ in 0..<20 { await Task.yield() }
        precondition(cancelled.count == 0, "a cancelled watch never fires")
    }

    static func scan(_ processes: KeepAwakeLiveProcesses) async -> [KeepAwakeHelperID]? {
        await withCheckedContinuation { done in processes.strays(olderThan: .max) { done.resume(returning: $0) } }
    }

    /// A real process exits on its own clock, so this waits in wall time rather than yields.
    static func waitReal(until done: () -> Bool) async {
        for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
        precondition(done(), "the process source never fired")
    }

    static func resultMapping() {
        let ok = Data("ok\n".utf8)
        precondition(KeepAwakeRootClient.result(exited: true, status: 0, reply: ok) == .ok)
        precondition(KeepAwakeRootClient.result(exited: true, status: 0, reply: Data("ok".utf8)) == .failed(0))
        precondition(KeepAwakeRootClient.result(exited: true, status: 69, reply: Data()) == .unsupported)
        precondition(KeepAwakeRootClient.result(exited: true, status: 1, reply: ok) == .failed(1))
        precondition(KeepAwakeRootClient.result(exited: false, status: 15, reply: ok) == .failed(-15))
    }

    // MARK: - Journal store

    static func store(_ root: URL, synced: @escaping (String) throws -> Void) throws -> KeepAwakeFileJournalStore {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return KeepAwakeFileJournalStore(url: root.appending(path: "a/b/journal.json"), root: root, syncFolder: synced)
    }

    static func storeEstablishesNewFolders(_ root: URL) throws {
        var synced: [String] = []
        let journal = try store(root) { synced.append($0) }
        let a = root.appending(path: "a").path, b = root.appending(path: "a/b").path
        try journal.save(Data("1".utf8))
        precondition(synced == [a, root.path, b], "new folders must be fsynced into their parents: \(synced)")
        synced = []
        try journal.save(Data("2".utf8))
        precondition(synced == [b], "an established folder only syncs its own entries: \(synced)")
        let second = try journal.load()
        precondition(second == Data("2".utf8))
        try FileManager.default.removeItem(atPath: b)
        synced = []
        try journal.save(Data("3".utf8))
        precondition(synced == [a, root.path, b], "a folder made again is fsynced again: \(synced)")
    }

    static func storeRetriesAFailedSync(_ root: URL) throws {
        struct SyncFailed: Error {}
        var synced: [String] = []
        var failing = true
        let journal = try store(root) { path in
            if failing, path == root.path { throw SyncFailed() }
            synced.append(path)
        }
        precondition(
            (try? journal.save(Data("1".utf8))) == nil, "an enable must not proceed while a new folder is not durable")
        failing = false
        synced = []
        try journal.save(Data("1".utf8))
        let a = root.appending(path: "a").path, b = root.appending(path: "a/b").path
        precondition(synced == [a, root.path, b], "the next save syncs the whole chain again: \(synced)")
    }

    static func storeKeepsRecordWhenWriteFails(_ root: URL) throws {
        let journal = try store(root) { _ in }
        let b = root.appending(path: "a/b").path
        try journal.save(Data("old".utf8))
        chmod(b, 0o500)
        defer { chmod(b, 0o700) }
        precondition((try? journal.save(Data("new".utf8))) == nil, "a write into a read-only folder must throw")
        let kept = try journal.load()
        precondition(kept == Data("old".utf8), "a failed write keeps the last record")
    }

    static func storeRefusesOutsideRoot(_ root: URL) throws {
        let inside = root.appending(path: "inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let other = root.appending(path: "other/journal.json")
        let journal = KeepAwakeFileJournalStore(url: other, root: inside) { _ in }
        do {
            try journal.save(Data("1".utf8))
            preconditionFailure("a journal outside its root must be refused")
        } catch KeepAwakeFileJournalStore.Failure.outsideRoot {}
        precondition(!FileManager.default.fileExists(atPath: other.deletingLastPathComponent().path), "nothing made")
    }

    static func storeLoadAndRemove(_ root: URL) throws {
        let journal = try store(root) { _ in }
        let empty = try journal.load()
        precondition(empty == nil, "no record reads as nil")
        try journal.save(Data("1".utf8))
        try journal.save(nil)
        let removed = try journal.load()
        precondition(removed == nil, "saving nil removes the record")
        try journal.save(nil)
        try FileManager.default.createDirectory(at: journal.url, withIntermediateDirectories: true)
        do {
            _ = try journal.load()
            preconditionFailure("an unreadable record must throw, so recovery still undoes")
        } catch {}
    }
}
