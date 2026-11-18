// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/SystemToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/KillProcessSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SudoTouchIDStore.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization
import SwiftUI

// Fakes stand in for `live`: no real process, no networkQuality, pam files only in scratch.
struct SudoTouchIDSettingsView: View {
    init(store: SudoTouchIDStore) {}
    var body: some View { EmptyView() }
}
extension SystemToolsSystem {
    static var live: Self { system }
}
extension SudoTouchIDFiles {
    static var live: Self { fatalError("the harness never writes the real pam files") }
}

final class FakeTapSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    private(set) var isRunning = true
    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }
    func stop() { isRunning = false }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var taps: [String: @MainActor () -> Void] = [:]
    var ended: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps[notice.id] = onTap
    }
    func end(notice id: String) { ended.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Everything the fake system saw; `feed` finishes the network run the module is waiting on.
@MainActor
final class Fake {
    var readings: [[ProcessSample]] = []
    var signals: [(pid: Int32, force: Bool)] = []
    var signalWorks = true
    var pickers = 0
    var closes = 0
    var sessions: [KillProcessSession] = []
    var networkRuns = 0
    var networkCancels = 0
    var feed: AsyncThrowingStream<Data, any Error>.Continuation?
    var questions: [String] = []
    var answer = false
}

@MainActor let fake = Fake()
let ticks = Atomic<UInt64>(0)
let second: UInt64 = 1_000_000_000

func sample(_ pid: Int32, _ name: String, cpu: UInt64, app: Bool = false) -> ProcessSample {
    ProcessSample(pid: pid, start: 7, name: name, isApp: app, cpuNanoseconds: cpu, memoryBytes: 1 << 20)
}

let system = SystemToolsSystem(
    ownPID: 4242,
    uptimeNanoseconds: { ticks.add(second, ordering: .relaxed).newValue },
    readProcesses: { fake.readings.isEmpty ? [] : fake.readings.removeFirst() },
    signal: { sample, force in
        fake.signals.append((sample.pid, force))
        return fake.signalWorks
    },
    presentPicker: { session, _ in
        fake.pickers += 1
        fake.sessions.append(session)
        return { fake.closes += 1 }
    },
    runNetworkQuality: {
        let (stream, feed) = AsyncThrowingStream<Data, any Error>.makeStream()
        await MainActor.run {
            fake.networkRuns += 1
            fake.feed = feed
        }
        for try await data in stream { return data }
        await MainActor.run { fake.networkCancels += 1 }
        throw CancellationError()
    })

/// Bounded turns of the run loop, never wall-clock time: a failed wait is a failed check.
@MainActor
func until(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<20_000 where !condition() { await Task.yield() }
    return condition()
}

@MainActor
final class Rig {
    let suite = "nc-SystemTools-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeTapSession($0) })
        controller = NotchcastController(
            addons: [SystemToolsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter,
            surfaces: NotchcastSurfaces(confirm: { title, _, _ in
                fake.questions.append(title)
                return fake.answer
            }))
        controller.start()
    }

    var context: NotchcastContext { controller.context(forSwitch: SystemToolsAddon.switchID)! }

    /// Switched on as a user would, so the core builds and starts the descriptor's module.
    func module() async -> SystemToolsModule {
        controller.preferences.set(SystemToolsAddon.switchID, on: true)
        _ = await until { context.module(SystemToolsModule.self) != nil }
        return context.module(SystemToolsModule.self)!
    }

    func finish() {
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

@main
@MainActor
enum SystemToolsModuleTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        await switchGatesCommands()
        await killByName()
        await forceQuitAsksFirst()
        await networkTestReportsResult()
        await networkTestCancels()
        await networkTestFails()
        await sudoTouchID()
        print("\(checks) system tools module checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func switchGatesCommands() async {
        let rig = Rig()
        defer { rig.finish() }
        check("the add-on is off by default", !rig.controller.preferences.isOn(SystemToolsAddon.switchID))
        check("off, no command is offered", rig.controller.enabledCommands.isEmpty)
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: true)
        check("on, both commands appear", await until { rig.controller.enabledCommands.count == 2 })
        check("on, its module runs", rig.context.module(SystemToolsModule.self) != nil)
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: false)
        check("off again, the commands go", await until { rig.controller.enabledCommands.isEmpty })
        check("off again, the module goes", rig.context.module(SystemToolsModule.self) == nil)
    }

    static func killByName() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.readings = [
            [sample(10, "Safari", cpu: 0, app: true), sample(11, "nc-test-sleeper", cpu: 0), sample(4242, "Notchcast", cpu: 0)],
            [sample(10, "Safari", cpu: second / 2, app: true), sample(11, "nc-test-sleeper", cpu: second / 4)],
        ]
        module.killProcess()
        guard fake.pickers == 1, let session = fake.sessions.last else { return check("the command opens the picker", false) }
        await session.refresh()
        check("the picker never lists Notchcast", !session.rows.contains { $0.sample.pid == 4242 })
        await session.refresh()
        check("the second reading has CPU", session.rows.first { $0.sample.pid == 10 }?.cpuPercent == 50)
        session.query = "SLEEP"
        check("typing filters by name", session.rows.map(\.sample.name) == ["nc-test-sleeper"])
        check("the match is selected", session.selectedPID == 11)
        let quit = await session.quit(session.rows[session.selectedIndex], force: false)
        check("Quit signals that process, not by force", quit && fake.signals.last.map { $0 == (11, false) } == true)
        check("Quit asks nothing", fake.questions.isEmpty)
        check("the outcome is a notice", rig.presenter.posts.last?.text.contains("nc-test-sleeper") == true)
        fake.signalWorks = false
        let gone = await session.quit(session.rows[0], force: false)
        check("a process already gone reports a failure", !gone && rig.presenter.posts.last?.isFailure == true)
        fake.signalWorks = true
        module.killProcess()
        check("a second Kill Process closes the first picker", fake.closes == 1 && fake.pickers == 2)
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: false)
        check("switching off closes the picker", await until { fake.closes == 2 })
        module.killProcess()
        check("a stopped module opens nothing", fake.pickers == 2)
    }

    static func forceQuitAsksFirst() async {
        let rig = Rig()
        defer { rig.finish() }
        fake.signals = []
        fake.questions = []
        let module = await rig.module()
        fake.readings = [[sample(30, "Stuck", cpu: 0, app: true)]]
        module.killProcess()
        guard let session = fake.sessions.last else { return check("the picker opens", false) }
        await session.refresh()
        fake.answer = false
        let declined = await session.quit(session.rows[0], force: true)
        check("Force Quit asks first", fake.questions.count == 1 && fake.questions[0].contains("Stuck"))
        check("declining signals nothing", !declined && fake.signals.isEmpty)
        fake.answer = true
        let forced = await session.quit(session.rows[0], force: true)
        check("accepting force quits that process", forced && fake.signals.last.map { $0 == (30, true) } == true)
    }

    static let fixture = Data(#"{"dl_throughput": 278390616, "ul_throughput": 21434567, "responsiveness": 1234}"#.utf8)

    static func networkTestReportsResult() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        let runs = fake.networkRuns
        module.testNetwork()
        let progress = rig.presenter.posts.last
        check("the test shows progress on the island",
              progress?.progress != nil && progress?.id == SystemToolsModule.networkNoticeID)
        check("Esc is listened for while it runs", rig.context.wantedTaps.count == 1)
        check("the tool runs once", await until { fake.networkRuns == runs + 1 })
        module.testNetwork()
        check("a second test while one runs is ignored", fake.networkRuns == runs + 1)
        fake.feed?.yield(fixture)
        check("the result replaces the progress", await until { rig.presenter.posts.last?.progress == nil })
        let result = rig.presenter.posts.last
        check("the result states the speeds (\(result?.text ?? ""))",
              result?.text.contains("Mbps") == true && result?.isFailure == false)
        check("the result stays long enough to read", result?.seconds == SystemToolsModule.resultSeconds)
        check("Esc is let go once it ends", rig.context.wantedTaps.isEmpty && !module.isTestingNetwork)
    }

    static func networkTestCancels() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        let runs = fake.networkRuns
        let cancels = fake.networkCancels
        module.testNetwork()
        _ = await until { fake.networkRuns == runs + 1 }
        guard let tap = rig.context.wantedTaps.first?.tap, case .observe(let handler) = tap.handler,
              let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
              let other = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        else { return check("the Esc tap observes keys", false) }
        handler(NotchcastTapEvent(type: .keyDown, event: other, syntheticTag: 0))
        check("another key leaves it running", module.isTestingNetwork)
        handler(NotchcastTapEvent(type: .keyDown, event: escape, syntheticTag: 0))
        check("Esc cancels", !module.isTestingNetwork && rig.presenter.posts.last?.text == "Network Test Cancelled")
        check("cancelling ends the tool", await until { fake.networkCancels == cancels + 1 })
        check("cancelling lets Esc go", rig.context.wantedTaps.isEmpty)
        let count = rig.presenter.posts.count
        fake.feed?.yield(fixture)
        for _ in 0..<200 { await Task.yield() }
        check("a cancelled run never reports late", rig.presenter.posts.count == count)

        module.testNetwork()
        _ = await until { fake.networkRuns == runs + 2 }
        rig.presenter.taps[SystemToolsModule.networkNoticeID]?()
        check("a click on the progress cancels too", !module.isTestingNetwork)
        module.testNetwork()
        _ = await until { fake.networkRuns == runs + 3 }
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: false)
        check("switching off ends the test and its notice",
              await until { !module.isTestingNetwork && rig.presenter.ended.last == SystemToolsModule.networkNoticeID })
    }

    static func networkTestFails() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        let runs = fake.networkRuns
        module.testNetwork()
        _ = await until { fake.networkRuns == runs + 1 }
        fake.feed?.yield(Data(#"{"error_code": -1009, "error_domain": "NSURLErrorDomain"}"#.utf8))
        check("a failed run ends with a failure notice", await until { rig.presenter.posts.last?.isFailure == true })
        check("the failure says so", rig.presenter.posts.last?.text == "Network Test Failed")
    }

    struct Declined: Error {}

    static func sudoTouchID() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-SystemTools-pam.\(UUID())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sudo = "auth       include        sudo_local\nauth       required       pam_opendirectory.so\n"
        try? sudo.write(to: folder.appending(path: "sudo"), atomically: true, encoding: .utf8)
        let local = folder.appending(path: "sudo_local")
        let writes = Mutex<[URL]>([])
        let outcome = Mutex<(any Error)?>(nil)
        let store = SudoTouchIDStore(files: SudoTouchIDFiles(directory: folder) { text, url in
            writes.withLock { $0.append(url) }
            if let error = outcome.withLock({ $0 }) { throw error }
            try text.write(to: url, atomically: true, encoding: .utf8)
        })
        store.refresh()
        check("no sudo_local reads as off", !store.isEnabled && store.isSupported)
        await store.set(true)
        check("on writes the rule and reads it back", store.isEnabled && writes.withLock { $0 } == [local])
        check("only the scratch folder is written", writes.withLock { $0 }.allSatisfy { $0.path.hasPrefix(folder.path) })
        await store.set(true)
        check("asking for on again writes nothing, so nothing asks for a password", writes.withLock { $0.count } == 1)
        let custom = "auth optional pam_reattach.so\n" + SudoTouchIDPolicy.rule + "\n"
        try? custom.write(to: local, atomically: true, encoding: .utf8)
        await store.set(false)
        check("off removes only the rule", !store.isEnabled
              && (try? String(contentsOf: local, encoding: .utf8)) == "auth optional pam_reattach.so\n")
        outcome.withLock { $0 = CancellationError() }
        await store.set(true)
        check("a declined password leaves it off, with no error", !store.isEnabled && !store.failed && !store.isBusy)
        outcome.withLock { $0 = Declined() }
        await store.set(true)
        check("a failed write is reported and the switch reads the file", !store.isEnabled && store.failed)
        outcome.withLock { $0 = nil }
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let before = writes.withLock { $0.count }
        await store.set(true)
        check("an unreadable sudo_local is never rewritten from nothing",
              store.failed && writes.withLock { $0.count } == before)
        try? FileManager.default.removeItem(at: local)
        try? "auth required pam_opendirectory.so\n".write(to: folder.appending(path: "sudo"), atomically: true, encoding: .utf8)
        await store.set(true)
        check("without the include the switch is unavailable and writes nothing",
              !store.isSupported && writes.withLock { $0.count } == before)
    }
}
