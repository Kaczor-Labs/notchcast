// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/SystemToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/KillProcessSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsPicking.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule+Addresses.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SudoTouchIDStore.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/nc-SystemTools-fixture.swift

import AppKit
import Foundation
import Synchronization

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
        await refreshKeepsRowOrder()
        await selectedProcessGone()
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
        check("on, all five commands appear", await until { rig.controller.enabledCommands.count == 5 })
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
        guard fake.pickers == 1, let session = fake.sessions.last as? KillProcessSession else {
            return check("the command opens the picker", false)
        }
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

    static func refreshKeepsRowOrder() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.readings = [
            [sample(10, "Calm", cpu: 0), sample(11, "Busy", cpu: 0)],
            [sample(10, "Calm", cpu: second / 4), sample(11, "Busy", cpu: second / 2)],
            [sample(10, "Calm", cpu: second), sample(11, "Busy", cpu: second / 2), sample(12, "Fresh", cpu: 0)],
        ]
        module.killProcess()
        guard let session = fake.sessions.last as? KillProcessSession else { return check("the picker opens", false) }
        await session.refresh()
        await session.refresh()
        check("the first CPU figures sort the rows once", session.rows.map(\.sample.pid) == [11, 10])
        session.selectedPID = 10
        await session.refresh()
        check("a refresh keeps the order and puts a new process last", session.rows.map(\.sample.pid) == [11, 10, 12])
        check("a refresh updates the figures in place", session.rows.map(\.cpuPercent) == [0, 75, 0])
        check("a refresh keeps the selection", session.selectedPID == 10)
        session.query = "a"
        check("a new query sorts again", session.rows.map(\.sample.pid) == [10])
        session.query = ""
        check("clearing the query sorts all rows", session.rows.map(\.sample.pid) == [10, 11, 12])
    }

    static func selectedProcessGone() async {
        let rig = Rig()
        defer { rig.finish() }
        fake.signals = []
        let module = await rig.module()
        fake.readings = [
            [sample(20, "Leaving", cpu: 0), sample(21, "Staying", cpu: 0)],
            [sample(21, "Staying", cpu: 0)],
        ]
        module.killProcess()
        guard let session = fake.sessions.last as? KillProcessSession else { return check("the picker opens", false) }
        await session.refresh()
        check("the first row is selected", session.selectedPID == 20)
        let closes = fake.closes
        await session.refresh()
        check("the selected process gone closes the picker", fake.closes == closes + 1)
        check("no other row takes the selection", session.selectedPID == 20)
        let notice = rig.presenter.posts.last
        check("the notice says it already quit", notice?.text == "Leaving Already Quit" && notice?.isFailure == false)
        check("nothing is signalled", fake.signals.isEmpty)
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: false)
        for _ in 0..<200 { await Task.yield() }
        check("a picker closed that way is not closed twice", fake.closes == closes + 1)
    }

    static func forceQuitAsksFirst() async {
        let rig = Rig()
        defer { rig.finish() }
        fake.signals = []
        fake.questions = []
        let module = await rig.module()
        fake.readings = [[sample(30, "Stuck", cpu: 0, app: true)]]
        module.killProcess()
        guard let session = fake.sessions.last as? KillProcessSession else { return check("the picker opens", false) }
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
        let garbles = Mutex(false)
        let store = SudoTouchIDStore(files: SudoTouchIDFiles(directory: folder) { text, url in
            writes.withLock { $0.append(url) }
            if let error = outcome.withLock({ $0 }) { throw error }
            try (garbles.withLock { $0 } ? "# other\n" : text).write(to: url, atomically: true, encoding: .utf8)
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
        garbles.withLock { $0 = true }
        await store.set(true)
        check("a file that differs from the text asked for is a failed write", !store.isEnabled && store.failed)
        garbles.withLock { $0 = false }
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
