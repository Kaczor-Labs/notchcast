// The fake Mac's processes and helper line the nc-KeepAwake harnesses share; never run on its own.
import Foundation

/// The process table and the sleep setting; shared by every rig, as one Mac outlives app launches.
@MainActor
final class FakeProcesses: KeepAwakeProcesses, KeepAwakeSleepSetting {
    static let shared = FakeProcesses()

    var sleepDisabled = false
    var unwatchable = false
    var unscannable = false
    var unreadableSleepSetting = false
    /// Runs as a scan starts: what a process does between the undo's ack and the scan reading the table.
    var beforeScan: (() -> Void)?
    /// Off, one process plays both sudo and the helper; on, sudo launches the helper as its child.
    var splitsSudo = false
    static let helperPath = "/fake/root-helper"
    static let me: Int32 = 500
    static let launchd = KeepAwakeProcess(id: .init(pid: 1, started: 0), parent: 0, executable: "/sbin/launchd")
    private var table: [Int32: KeepAwakeProcess] = [1: launchd]
    private var watches: [FakeWatch] = []
    private var lastPID: Int32 = 1000
    private var lastStart: Int64 = 0

    func spawn(pid: Int32? = nil, _ executable: String = "/bin/other", parent: Int32 = FakeProcesses.me) -> Int32 {
        let pid = pid ?? {
            lastPID += 1
            return lastPID
        }()
        lastStart += 1
        table[pid] = KeepAwakeProcess(id: .init(pid: pid, started: lastStart), parent: parent, executable: executable)
        return pid
    }

    /// The fork child of sudo becoming the root helper.
    func exec(_ pid: Int32) { table[pid]?.executable = Self.helperPath }

    func strays(olderThan undo: Int64, _ found: @escaping @MainActor @Sendable ([KeepAwakeHelperID]?) -> Void) {
        beforeScan?()
        let live = table.values.sorted { $0.id.pid < $1.id.pid }
        found(unscannable ? nil : KeepAwakeStrays.older(than: undo, in: live, helperPath: Self.helperPath, me: Self.me))
    }

    func identify(_ pid: Int32) -> KeepAwakeHelperID? { table[pid]?.id }

    func watch(
        _ helper: KeepAwakeHelperID, exited: @escaping @MainActor @Sendable () -> Void
    ) -> (any KeepAwakeProcessWatch)? {
        guard !unwatchable else { return nil }
        let watch = FakeWatch(helper, exited)
        watches.append(watch)
        if identify(helper.pid) != helper { Task { @MainActor in watch.fire() } }
        return watch
    }

    func isDisabled(_ found: @escaping @MainActor @Sendable (Bool?) -> Void) {
        found(unreadableSleepSetting ? nil : sleepDisabled)
    }

    /// What a helper's pmset call does to the Mac, whoever is still listening for its reply.
    func land(_ verb: KeepAwakeSleepVerb) { sleepDisabled = verb == .batterySleepOff }

    /// Orphans go to launchd, as the kernel reparents them.
    func exit(_ pid: Int32) {
        table[pid] = nil
        for (child, process) in table where process.parent == pid { table[child]?.parent = 1 }
        watches.filter { $0.helper.pid == pid }.forEach { $0.fire() }
    }

    func isAlive(_ pid: Int32) -> Bool { table[pid] != nil }
    var watching: Int { watches.filter(\.isArmed).count }
}

@MainActor
final class FakeWatch: KeepAwakeProcessWatch {
    let helper: KeepAwakeHelperID
    private var exited: (@MainActor @Sendable () -> Void)?

    init(_ helper: KeepAwakeHelperID, _ exited: @escaping @MainActor @Sendable () -> Void) {
        self.helper = helper
        self.exited = exited
    }

    var isArmed: Bool { exited != nil }
    func cancel() { exited = nil }

    func fire() {
        let exited = exited
        self.exited = nil
        exited?()
    }
}

/// One app launch's helper line: calls launch one at a time, and each answers only when told.
@MainActor
final class FakeLine {
    typealias Call = (
        owner: ObjectIdentifier, verb: KeepAwakeSleepVerb, launched: @MainActor (Int32) -> Void,
        done: @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    )

    let machine: FakeProcesses
    private var waiting: [Call] = []
    private(set) var current: (pid: Int32, child: Int32, call: Call)?

    init(_ machine: FakeProcesses = .shared) { self.machine = machine }

    func send(_ call: Call) {
        waiting.append(call)
        startNext()
    }

    func reply(_ owner: ObjectIdentifier, _ result: KeepAwakeHelperResult) {
        guard let current, current.call.owner == owner else { preconditionFailure("no helper call of this rig is out") }
        self.current = nil
        if result == .ok { machine.land(current.call.verb) }
        machine.exit(current.child)
        machine.exit(current.pid)
        current.call.done(result)
        startNext()
    }

    func isWaiting(_ owner: ObjectIdentifier) -> Bool {
        current?.call.owner == owner || waiting.contains { $0.owner == owner }
    }

    private func startNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        let pid = machine.spawn(machine.splitsSudo ? KeepAwakeStrays.sudo : FakeProcesses.helperPath)
        current = (pid, machine.splitsSudo ? machine.spawn(FakeProcesses.helperPath, parent: pid) : pid, next)
        next.launched(pid)
    }
}

/// A module's view of the line: it logs what this rig sent and answers only this rig's calls.
@MainActor
final class FakeHelper: KeepAwakeSleepHelper {
    let line: FakeLine
    var isInstalled = true
    var sent: [KeepAwakeSleepVerb] = []

    init(line: FakeLine = FakeLine()) { self.line = line }

    func send(
        _ verb: KeepAwakeSleepVerb, launched: @escaping @MainActor (Int32) -> Void,
        done: @escaping @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    ) {
        sent.append(verb)
        line.send((ObjectIdentifier(self), verb, launched, done))
    }

    func isRunning(_ pid: Int32) -> Bool { line.current?.pid == pid }

    var isWaiting: Bool { line.isWaiting(ObjectIdentifier(self)) }

    /// The pid of this rig's call now running, which a crash leaves alive.
    var runningPID: Int32? { line.current.flatMap { $0.call.owner == ObjectIdentifier(self) ? $0.pid : nil } }

    /// The root helper sudo launched for that call; the same process unless the Mac splits sudo.
    var runningChild: Int32? { line.current.flatMap { $0.call.owner == ObjectIdentifier(self) ? $0.child : nil } }

    func reply(_ result: KeepAwakeHelperResult = .ok) { line.reply(ObjectIdentifier(self), result) }
}
