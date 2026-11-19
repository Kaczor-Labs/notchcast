// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScriptCommands/ScriptCommandsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScriptCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScriptCommands/Service/ScriptCommandsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScriptCommands/Service/ScriptCommandsSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization
import SwiftUI

// The shipped `live`, process and settings view are left out: no real process or clock is used.

struct ScriptCommandsSettingsView: View {
    let context: NotchcastContext
    var body: some View { EmptyView() }
}

/// A script that exits only when the harness says so, or when it is terminated.
final class FakeProcess: ScriptProcess {
    private struct State {
        var exit: ScriptExit?
        var waiter: CheckedContinuation<ScriptExit, Never>?
        var terminations = 0
    }

    let invocation: ScriptInvocation
    private let state = Mutex(State())

    init(_ invocation: ScriptInvocation) { self.invocation = invocation }

    var terminations: Int { state.withLock { $0.terminations } }

    func waitForExit() async -> ScriptExit {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> ScriptExit? in
                if state.exit == nil { state.waiter = continuation }
                return state.exit
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func exit(_ status: Int32, _ output: String = "") {
        let waiter = state.withLock { state -> CheckedContinuation<ScriptExit, Never>? in
            guard state.exit == nil else { return nil }
            state.exit = ScriptExit(status: status, output: output)
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: ScriptExit(status: status, output: output))
    }

    /// A terminated shell exits 143, as SIGTERM leaves it.
    func terminate() {
        state.withLock { $0.terminations += 1 }
        exit(143, "Terminated\n")
    }
}

/// A timeout that fires only when the harness fires it; cancelling it throws, as `Task.sleep` does.
final class FakeSleeper: Sendable {
    private struct Pending {
        var duration: Duration
        var continuation: CheckedContinuation<Void, any Error>
    }

    private let pending = Mutex<[UUID: Pending]>([:])

    var durations: [Duration] { pending.withLock { $0.values.map(\.duration) } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.withLock { $0[id] = Pending(duration: duration, continuation: continuation) }
                if Task.isCancelled { resume(id, throwing: true) }
            }
        } onCancel: {
            resume(id, throwing: true)
        }
    }

    func fireAll() { for id in pending.withLock({ Array($0.keys) }) { resume(id, throwing: false) } }

    private func resume(_ id: UUID, throwing: Bool) {
        guard let entry = pending.withLock({ $0.removeValue(forKey: id) }) else { return }
        if throwing { entry.continuation.resume(throwing: CancellationError()) } else { entry.continuation.resume() }
    }
}

final class FakeMac: Sendable {
    let sleeper = FakeSleeper()
    private let launched = Mutex<[FakeProcess]>([])
    let folders: Set<String> = ["/tmp/me", "/tmp"]

    var processes: [FakeProcess] { launched.withLock { $0 } }

    func launch(_ invocation: ScriptInvocation) -> any ScriptProcess {
        let process = FakeProcess(invocation)
        launched.withLock { $0.append(process) }
        return process
    }
}

let mac = FakeMac()
let ids = Mutex(0)

extension ScriptCommandsSystem {
    static let live = ScriptCommandsSystem(
        environment: {
            ScriptInvocation.Environment(
                shell: "/bin/zsh", home: "/tmp/me", isExecutableFile: { _ in false },
                isDirectory: { mac.folders.contains($0) })
        },
        launch: { mac.launch($0) },
        sleep: { try await mac.sleeper.sleep($0) },
        makeID: { ids.withLock { $0 += 1; return "id\($0)" } })
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController
    var published: [[String]] = []

    init(suite: String, on: Bool) {
        defaults = UserDefaults(suiteName: suite)!
        if on { defaults.set(true, forKey: ScriptCommandsAddon.switchID) }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [ScriptCommandsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter)
        controller.onCommandsChanged = { [unowned self] in published.append($0.map { "\($0.id)=\($0.name)" }) }
        controller.start()
    }

    var module: ScriptCommandsModule? {
        controller.context(forSwitch: ScriptCommandsAddon.switchID)?.module(ScriptCommandsModule.self)
    }

    var last: IslandNotice? { presenter.posts.last }

    /// Yields until the condition holds; a bounded count of turns, never a clock.
    func settle(_ label: String, until condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
        precondition(condition(), "\(label): never happened")
    }
}

func expectResult(_ notice: IslandNotice?, _ text: String, failure: Bool, _ label: String) {
    guard let notice else { preconditionFailure("\(label): no notice") }
    precondition(notice.text == text, "\(label): text was \(notice.text)")
    precondition(notice.isFailure == failure && notice.progress == nil, "\(label): a result, not progress")
    precondition(notice.symbol == (failure ? "terminal" : "checkmark"), "\(label): symbol")
}

@main
enum ScriptCommandsModuleTests {
    @MainActor
    static func main() async {
        precondition(ScriptCommandsAddon.switches.map(\.id) == ["scriptCommands"], "switch id")
        precondition(ScriptCommandsAddon.switches[0].defaultEnabled == false, "off by default")
        precondition(ScriptCommandsAddon.switches[0].category == .launcher, "Launcher Extras")
        precondition(ScriptCommandsAddon.commands.isEmpty, "every command comes from a row")

        let suite = "nc-ScriptCommands-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var rig = Rig(suite: suite, on: false)
        precondition(rig.module == nil, "off: no module")
        rig.controller.preferences.set(ScriptCommandsAddon.switchID, on: true)
        await rig.settle("switch on starts the module") { rig.module?.isRunning == true }
        guard let module = rig.module else { preconditionFailure("module") }

        // A row becomes a launcher command once it has a name and a script.
        let id = module.addRow()
        precondition(rig.controller.enabledCommands.isEmpty, "an empty row makes no command")
        module.update(ScriptCommand(id: id, name: "Update packages", script: "brew update && brew upgrade"))
        let entryID = "command:nc-run-" + id
        precondition(rig.controller.enabledCommands.map(\.id) == [entryID], "the row's command is live")
        precondition(rig.published.last == [entryID + "=Update packages"], "the launcher and hotkeys get it")
        module.update(ScriptCommand(id: id, name: "Upgrade", script: "brew update && brew upgrade"))
        precondition(rig.published.last == [entryID + "=Upgrade"], "a rename republishes under the same id")
        module.update(ScriptCommand(id: id, name: "Update packages", script: "brew update && brew upgrade"))

        // Acceptance 1: runs from the launcher, no terminal, spinner, then a success notice.
        precondition(rig.controller.run(entryID: entryID), "the launcher runs it")
        await rig.settle("launched") { mac.processes.count == 1 && mac.sleeper.durations.count == 1 }
        let first = mac.processes[0]
        precondition(first.invocation.shell == "/bin/zsh", "login shell")
        precondition(first.invocation.arguments == ["-lc", "brew update && brew upgrade"], "the command")
        precondition(first.invocation.folder == "/tmp/me", "home folder")
        precondition(mac.sleeper.durations == [.seconds(1800)], "30 minute timeout")
        let progress = rig.last
        precondition(progress?.text == "Update packages" && progress?.progress != nil, "the name with a spinner")
        precondition(progress?.id == ScriptCommandsModule.noticeID(id), "one notice per row")
        precondition(module.running == [id], "the row shows as running")

        // A second run while it runs is refused with a notice and starts nothing.
        precondition(rig.controller.run(entryID: entryID), "the second press reaches the module")
        expectBusy(rig.last)
        precondition(mac.processes.count == 1, "no second process")

        first.exit(0, "==> Upgrading 2 outdated packages\n==> Upgraded\n")
        await rig.settle("finished") { module.running.isEmpty }
        expectResult(rig.last, "Update packages finished", failure: false, "success")
        precondition(rig.last?.id == ScriptCommandsModule.noticeID(id), "the result replaces the spinner")
        precondition(module.outputs[id] == "==> Upgrading 2 outdated packages\n==> Upgraded\n", "full output kept")
        precondition(first.terminations == 0, "a clean exit is never terminated")
        await rig.settle("timer cancelled") { mac.sleeper.durations.isEmpty }

        // Acceptance 2: exit 1 shows a failure notice with the script's last line.
        _ = rig.controller.run(entryID: entryID)
        await rig.settle("second launch") { mac.processes.count == 2 }
        mac.processes[1].exit(1, "Updating Homebrew...\nError: No such keg: /opt/homebrew/Cellar/x\n")
        await rig.settle("failed") { module.running.isEmpty }
        expectResult(rig.last, "Update packages failed (exit 1): Error: No such keg: /opt/homebrew/Cellar/x",
                     failure: true, "failure")

        // The timeout terminates the process group and says so.
        module.update(ScriptCommand(id: id, name: "Update packages", script: "brew update && brew upgrade",
                                    timeoutMinutes: 5))
        _ = rig.controller.run(entryID: entryID)
        await rig.settle("third launch") { mac.processes.count == 3 && mac.sleeper.durations == [.seconds(300)] }
        mac.sleeper.fireAll()
        await rig.settle("timed out") { module.running.isEmpty }
        precondition(mac.processes[2].terminations == 1, "the group is terminated")
        expectResult(rig.last, "Update packages stopped after 5 min", failure: true, "timeout")

        // A folder that is gone fails before anything starts.
        module.update(ScriptCommand(id: id, name: "Update packages", script: "make", folder: "~/Gone"))
        _ = rig.controller.run(entryID: entryID)
        precondition(mac.processes.count == 3, "nothing starts in a missing folder")
        expectResult(rig.last, "Update packages could not start: no folder at ~/Gone", failure: true, "folder")
        module.update(ScriptCommand(id: id, name: "Update packages", script: "brew update && brew upgrade"))

        // Rows persist; a relaunch publishes them again.
        rig.controller.stop()
        rig = Rig(suite: suite, on: true)
        await rig.settle("relaunch") { rig.module?.isRunning == true }
        precondition(rig.controller.enabledCommands.map(\.id) == [entryID], "stored rows come back as commands")
        guard let relaunched = rig.module else { preconditionFailure("module") }
        precondition(relaunched.rows.first?.script == "brew update && brew upgrade", "the row is stored")

        // Switching off mid-run terminates it, ends the spinner and posts nothing late.
        _ = rig.controller.run(entryID: entryID)
        await rig.settle("fourth launch") { mac.processes.count == 4 }
        let posted = rig.presenter.posts.count
        rig.controller.preferences.set(ScriptCommandsAddon.switchID, on: false)
        await rig.settle("switch off") { rig.module == nil }
        await rig.settle("terminated") { mac.processes[3].terminations == 1 }
        precondition(rig.presenter.ends.last == ScriptCommandsModule.noticeID(id), "the spinner is ended")
        precondition(rig.controller.enabledCommands.isEmpty, "commands go with the switch")
        for _ in 0..<100 { await Task.yield() }
        precondition(rig.presenter.posts.count == posted, "a cancelled run posts no result")
        precondition(!rig.controller.run(entryID: entryID), "an off switch runs nothing")

        // Deleting a row mid-run terminates it and removes its command.
        rig.controller.preferences.set(ScriptCommandsAddon.switchID, on: true)
        await rig.settle("back on") { rig.module?.isRunning == true }
        _ = rig.controller.run(entryID: entryID)
        await rig.settle("fifth launch") { mac.processes.count == 5 }
        rig.module?.removeRow(id)
        await rig.settle("removed") { mac.processes[4].terminations == 1 }
        precondition(rig.controller.enabledCommands.isEmpty && rig.module?.rows.isEmpty == true, "the row is gone")
        rig.controller.stop()

        print("PASS: script commands module covers commands per row, runs, refusal, results, timeout and teardown")
    }

    static func expectBusy(_ notice: IslandNotice?) {
        precondition(notice?.text == "Update packages is already running", "refused: \(notice?.text ?? "none")")
        precondition(notice?.progress == nil, "the refusal is a plain notice")
    }
}
