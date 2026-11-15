// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/QuitProtectionAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/QuitProtection/Service/QuitProtectionSystem.swift

import AppKit
import CoreGraphics
import Synchronization
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct QuitProtectionSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let editor = QuitProtectionEngine.Target(processIdentifier: 42, bundleIdentifier: "test.editor", name: "Editor")
let clock = Mutex<TimeInterval>(100)
let uptimeReads = Mutex(0)

@MainActor
final class FakeSystem {
    var frontmost: QuitProtectionEngine.Target? = editor
    var terminateSucceeds = true
    var terminated: [Int32] = []
    var posted: [[Int]] = []
}

@MainActor let fake = FakeSystem()

extension QuitProtectionSystem {
    static let live = QuitProtectionSystem(
        uptime: {
            uptimeReads.withLock { $0 += 1 }
            return clock.withLock { $0 }
        },
        frontmost: { fake.frontmost },
        commandCharacter: { [12: "q", 13: "w", 0: "a"][$0] },
        terminate: { pid in
            guard fake.terminateSucceeds else { return false }
            fake.terminated.append(pid)
            return true
        },
        post: { pid, keyCode in fake.posted.append([Int(pid), Int(keyCode)]) }
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
final class FakePresenter: NotchcastPresenting {
    var posts: [NotchcastNotice] = []
    var ends: [UUID] = []
    var levels: [NotchcastLevel] = []

    var isShowing: Bool { posts.last.map { !ends.contains($0.id) } ?? false }

    func showLevel(_ level: NotchcastLevel) { levels.append(level) }
    func post(_ notice: NotchcastNotice) { posts.append(notice) }
    func end(_ noticeID: UUID) { ends.append(noticeID) }
    func setStatus(_ status: NotchcastStatus?, owner: String) {}
    func setMenuRows(_ rows: [NotchcastMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
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
            addons: [QuitProtectionAddon.self], defaults: defaults, hub: hub, presenter: presenter)
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

func drain() async { try? await Task.sleep(for: .milliseconds(120)) }
func advance(to time: TimeInterval) { clock.withLock { $0 = time } }

@main
enum QuitProtectionModuleTests {
    @MainActor
    static func main() async {
        var rig = Rig()
        let presenter = rig.presenter
        precondition(rig.session?.isRunning == true, "default-on switch installs the tap")

        advance(to: 100)
        precondition(rig.key(12) == .swallow, "⌘Q arms")
        await drain()
        precondition(presenter.posts.last?.title == "Hold ⌘Q to quit Editor", "notice names the app")
        precondition(presenter.posts.last?.isProgress == true && presenter.isShowing, "notice stays up")
        advance(to: 100.4)
        await drain()
        precondition(presenter.levels.last.map { abs($0.value - 0.5) < 1e-9 && $0.symbol == "power" } == true,
                     "hold progress goes through showLevel")
        precondition(fake.terminated.isEmpty, "nothing quits before 0.8 s")
        advance(to: 100.8)
        await drain()
        precondition(fake.terminated == [42] && fake.posted.isEmpty, "0.8 s hold terminates natively")
        precondition(!presenter.isShowing, "the notice ends on confirm")
        precondition(rig.key(12, down: false) == .swallow, "the confirming release is swallowed")

        fake.terminateSucceeds = false
        advance(to: 110)
        rig.key(12)
        advance(to: 110.8)
        await drain()
        precondition(fake.posted == [[42, 12]], "a refused terminate falls back to a posted ⌘Q")
        rig.key(12, down: false)
        fake.terminateSucceeds = true

        advance(to: 120)
        rig.key(12)
        fake.frontmost = .init(processIdentifier: 43, bundleIdentifier: "test.other", name: "Other")
        advance(to: 120.8)
        await drain()
        precondition(fake.terminated == [42] && fake.posted == [[42, 12]], "a target no longer frontmost is spared")
        rig.key(12, down: false)
        fake.frontmost = editor
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        rig.defaults.set(true, forKey: QuitProtectionStore.closeEnabledKey)
        await drain()
        advance(to: 125)
        precondition(rig.key(13) == .swallow, "⌘W arms once enabled")
        advance(to: 125.8)
        await drain()
        precondition(fake.posted.last == [42, 13] && fake.terminated == [42], "⌘W closes by a posted ⌘W")
        rig.key(13, down: false)

        rig.defaults.set("doublePress", forKey: QuitProtectionStore.modeKey)
        await drain()
        let levels = presenter.levels.count
        advance(to: 130)
        precondition(rig.key(12) == .swallow, "first press swallowed")
        rig.key(12, down: false)
        await drain()
        precondition(presenter.posts.last?.title == "Press ⌘Q again to quit Editor", "double-press notice")
        advance(to: 130.5)
        precondition(rig.key(12) == .swallow, "second press swallowed")
        await drain()
        precondition(fake.terminated == [42, 42], "double press within 0.6 s quits")
        precondition(presenter.levels.count == levels, "double press shows no hold level")
        rig.key(12, down: false)

        advance(to: 140)
        rig.key(12)
        rig.key(12, down: false)
        precondition(rig.key(53, []) == .swallow, "Esc is swallowed while armed")
        precondition(rig.key(53, [], down: false) == .swallow, "its release too")
        await drain()
        precondition(!presenter.isShowing, "Esc ends the notice")
        advance(to: 140.3)
        rig.key(12)
        await drain()
        precondition(fake.terminated == [42, 42] && presenter.isShowing, "after Esc a press arms again")
        rig.key(12, down: false)
        advance(to: 141)
        await drain()

        rig.defaults.set("hold", forKey: QuitProtectionStore.modeKey)
        await drain()
        let posts = presenter.posts.count
        advance(to: 150)
        precondition(rig.key(48) == .pass, "⌘Tab passes")
        precondition(rig.key(12) == .pass, "⌘Q in the app switcher passes")
        rig.key(12, down: false)
        advance(to: 151)
        await drain()
        precondition(presenter.posts.count == posts && fake.terminated == [42, 42], "⌘Tab never arms")
        rig.flags([])

        advance(to: 160)
        precondition(rig.key(12) == .swallow, "arms again after ⌘ is released")
        await drain()
        precondition(presenter.isShowing, "half-armed")
        precondition(rig.session!.router.receive(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!) == .reenable)
        await drain()
        precondition(!presenter.isShowing, "the tap's reset ends the notice")
        advance(to: 161)
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
        await drain()
        precondition(uptimeReads.withLock { $0 } - reads == 5, "events that change nothing never hop to main")

        advance(to: 170)
        rig.key(12)
        await drain()
        rig.controller.stop()
        precondition(!presenter.isShowing, "stop ends the notice")
        advance(to: 171)
        await drain()
        precondition(fake.terminated == [42, 42], "a hold armed before stop never fires")
        rig.finish()

        rig = Rig()
        rig.controller.preferences.set(QuitProtectionAddon.switchID, on: false)
        await drain()
        precondition(rig.hub.subscriberCount == 0 && rig.session?.isRunning == false, "switch off removes the tap")
        rig.finish()
        print("nc-QuitProtection-module-test: PASS")
    }
}
