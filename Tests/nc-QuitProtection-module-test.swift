// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/QuitProtectionAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct QuitProtectionSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let editor = QuitProtectionEngine.Target(processIdentifier: 42, bundleIdentifier: "test.editor")
let clock = Mutex<TimeInterval>(100)
let uptimeReads = Mutex(0)
/// The module's own workspace center, so another process coming forward never reaches it.
let workspaceCenter = NotificationCenter()

@MainActor
final class FakeSystem {
    var frontmost: QuitProtectionEngine.Target? = editor
    var terminateSucceeds = true
    var terminated: [Int32] = []
    var posted: [[Int]] = []
    var sleepers: [(deadline: TimeInterval, wake: CheckedContinuation<Void, Never>)] = []

    /// The ticker's sleep: it wakes only when `advance` moves the fake uptime past its deadline.
    func sleep(_ duration: Duration) async {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let deadline = clock.withLock { $0 } + seconds
        await withCheckedContinuation { sleepers.append((deadline, $0)) }
    }
}

@MainActor let fake = FakeSystem()

extension QuitProtectionSystem {
    static let live = QuitProtectionSystem(
        uptime: {
            uptimeReads.withLock { $0 += 1 }
            return clock.withLock { $0 }
        },
        frontmost: { fake.frontmost },
        workspaceNotifications: { workspaceCenter },
        commandCharacter: { [12: "q", 13: "w", 0: "a"][$0] },
        terminate: { pid in
            guard fake.terminateSucceeds else { return false }
            fake.terminated.append(pid)
            return true
        },
        post: { pid, keyCode in fake.posted.append([Int(pid), Int(keyCode)]) },
        sleep: { await fake.sleep($0) }
    )
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
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    var levels: [IslandLevel] = []

    func showLevel(_ level: IslandLevel) { levels.append(level) }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite = "nc-QuitProtection-test.\(UUID())"
    let defaults: UserDefaults
    let hub: NotchcastTapHub
    let presenter = FakePresenter()
    let controller: NotchcastController
    var session: FakeSession?

    init() {
        defaults = UserDefaults(suiteName: suite)!
        var made: FakeSession?
        hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: {
            let session = FakeSession($0)
            made = session
            return session
        })
        controller = NotchcastController(
            addons: [QuitProtectionAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
        controller.start()
        session = made
    }

    @discardableResult
    func key(
        _ code: Int, _ flags: CGEventFlags = .maskCommand, down: Bool = true, repeat: Bool = false
    ) -> NotchcastTapRouter.Outcome {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = flags
        if `repeat` { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return session!.router.receive(type: down ? .keyDown : .keyUp, event: event)
    }

    @discardableResult
    func flags(_ flags: CGEventFlags) -> NotchcastTapRouter.Outcome {
        let event = CGEvent(source: nil)!
        event.type = .flagsChanged
        event.flags = flags
        return session!.router.receive(type: .flagsChanged, event: event)
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// Every hop the module makes lands on the main actor, so yielding runs them in order.
@MainActor func drain() async { for _ in 0..<10 { await Task.yield() } }

/// Lets started tasks park first, then wakes every ticker sleep the new uptime has reached.
@MainActor func advance(to time: TimeInterval) async {
    await drain()
    clock.withLock { $0 = time }
    let due = fake.sleepers.filter { $0.deadline <= time }
    fake.sleepers.removeAll { $0.deadline <= time }
    for sleeper in due { sleeper.wake.resume() }
    await drain()
}

@main
enum QuitProtectionModuleTests {
    @MainActor
    static func main() async {
        var rig = Rig()
        let presenter = rig.presenter
        precondition(rig.session?.isRunning == true, "default-on switch installs the tap")

        await advance(to: 100)
        precondition(rig.key(12) == .swallow, "⌘Q arms")
        await advance(to: 100.4)
        await drain()
        precondition(fake.terminated.isEmpty, "nothing quits before 0.8 s")
        await advance(to: 100.8)
        await drain()
        precondition(fake.terminated == [42] && fake.posted.isEmpty, "0.8 s hold terminates natively")
        precondition(rig.key(12, down: false) == .swallow, "the confirming release is swallowed")
        precondition(presenter.posts.isEmpty && presenter.levels.isEmpty, "a full hold posts no notice or level")

        fake.terminateSucceeds = false
        await advance(to: 110)
        rig.key(12)
        await advance(to: 110.8)
        await drain()
        precondition(fake.posted == [[42, 12]], "a refused terminate falls back to a posted ⌘Q")
        rig.key(12, down: false)
        fake.terminateSucceeds = true

        await advance(to: 120)
        rig.key(12)
        fake.frontmost = .init(processIdentifier: 43, bundleIdentifier: "test.other")
        await advance(to: 120.8)
        await drain()
        precondition(fake.terminated == [42] && fake.posted == [[42, 12]], "a target no longer frontmost is spared")
        rig.key(12, down: false)
        fake.frontmost = editor
        workspaceCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        rig.defaults.set(true, forKey: QuitProtectionStore.closeEnabledKey)
        await drain()
        await advance(to: 125)
        precondition(rig.key(13) == .swallow, "⌘W arms once enabled")
        await advance(to: 125.8)
        await drain()
        precondition(fake.posted.last == [42, 13] && fake.terminated == [42], "⌘W closes by a posted ⌘W")
        rig.key(13, down: false)

        rig.defaults.set("doublePress", forKey: QuitProtectionStore.modeKey)
        await drain()
        await advance(to: 130)
        precondition(rig.key(12) == .swallow, "first press swallowed")
        rig.key(12, down: false)
        await drain()
        await advance(to: 130.5)
        precondition(rig.key(12) == .swallow, "second press swallowed")
        await drain()
        precondition(fake.terminated == [42, 42], "double press within 0.6 s quits")
        rig.key(12, down: false)
        await drain()
        precondition(presenter.posts.isEmpty && presenter.levels.isEmpty && presenter.ends.isEmpty,
                     "a full double press posts no notice or level")

        await advance(to: 140)
        rig.key(12)
        rig.key(12, down: false)
        precondition(rig.key(53, []) == .swallow, "Esc is swallowed while armed")
        precondition(rig.key(53, [], down: false) == .swallow, "its release too")
        await advance(to: 140.3)
        rig.key(12)
        await drain()
        precondition(fake.terminated == [42, 42], "after Esc a press arms again instead of quitting")
        rig.key(12, down: false)
        await advance(to: 141)
        await drain()

        rig.defaults.set("hold", forKey: QuitProtectionStore.modeKey)
        await drain()
        await advance(to: 150)
        precondition(rig.key(48) == .pass, "⌘Tab passes")
        precondition(rig.key(12) == .pass, "⌘Q in the app switcher passes")
        rig.key(12, down: false)
        await advance(to: 151)
        await drain()
        precondition(fake.terminated == [42, 42], "⌘Tab never arms")
        rig.flags([])

        await advance(to: 160)
        precondition(rig.key(12) == .swallow, "arms again after ⌘ is released")
        await drain()
        guard case .reenable(let ids) = rig.session!.router.receive(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        else { preconditionFailure("a disable notice re-enables") }
        rig.session!.router.reenabled(ids)
        await drain()
        await advance(to: 161)
        await drain()
        precondition(fake.terminated == [42, 42], "reset clears the half-armed hold")
        precondition(rig.key(12, down: false) == .pass, "reset forgets the swallowed release")

        rig.defaults.set([editor.bundleIdentifier], forKey: QuitProtectionStore.exceptionsKey)
        await drain()
        precondition(rig.key(12) == .pass, "an exception keeps its own ⌘Q")
        rig.key(12, down: false)
        rig.defaults.removeObject(forKey: QuitProtectionStore.exceptionsKey)
        await drain()

        let reads = uptimeReads.withLock { $0 }
        rig.key(0, [])
        rig.key(0, [], down: false)
        rig.key(0)
        rig.flags([.maskShift])
        rig.flags([])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await drain()
        precondition(uptimeReads.withLock { $0 } - reads == 5, "events that change nothing never hop to main")

        await advance(to: 170)
        rig.key(12)
        await drain()
        rig.controller.stop()
        await advance(to: 171)
        await drain()
        precondition(fake.terminated == [42, 42], "a hold armed before stop never fires")
        precondition(presenter.posts.isEmpty && presenter.ends.isEmpty, "stop and reset leave nothing to end")
        rig.finish()

        rig = Rig()
        rig.controller.preferences.set(QuitProtectionAddon.switchID, on: false)
        await drain()
        precondition(rig.hub.subscriberCount == 0 && rig.session?.isRunning == false, "switch off removes the tap")
        rig.finish()
        print("nc-QuitProtection-module-test: PASS")
    }
}
