// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit
import CoreGraphics
import Foundation

@main
@MainActor
struct NotchcastTapTest {
    static var failures = 0
    static var checks = 0

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    /// Delivery and reconcile both hop through the main queue, so the run loop must turn.
    static func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func main() {
        hub()
        trustMonitor()
        print(failures == 0 ? "PASS NotchcastTapTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static func hub() {
        let system = FakeSystem()
        let hub = system.makeHub()
        let subs = Subscriptions(hub)
        let keyMask = NotchcastTapPolicy.mask(for: .keyDown)
        check("no session without subscribers", system.sessions.isEmpty && !hub.isRunning)

        var seen: [Int64] = []
        var resets: [String] = []
        let first = subs.add(NotchcastTap(
            switchID: "a", mask: keyMask, handler: .observe { seen.append($0.keyCode) }, reset: { resets.append("a") }))
        let second = subs.add(NotchcastTap(
            switchID: "b", mask: keyMask, handler: .observe { _ in }, reset: { resets.append("b") }))
        check("one shared session", system.sessions.count == 1 && hub.isRunning)
        check("observers alone listen only", system.live?.options == .listenOnly)

        let key = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true)!
        check("an observed event passes", system.live?.router.receive(type: .keyDown, event: key) == .pass)
        drain()
        check("observers get the event on main", seen == [7])
        key.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        _ = system.live?.router.receive(type: .keyDown, event: key)
        drain()
        check("our own synthetic events are skipped", seen == [7])

        guard case .reenable(let disabled)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a disable notice re-enables, naming its subscribers", false)
        }
        check("a disable notice re-enables, naming its subscribers", disabled.count == 2)
        drain()
        check("no reset before the tap is re-enabled", resets.isEmpty)
        system.live?.router.reenabled(disabled)
        subs.remove(second)
        drain()
        check("reset reaches live subscribers only, once", resets == ["a"])
        check("same mask keeps the session", system.sessions.count == 1)
        let probe = subs.add(NotchcastTap(
            switchID: "p", mask: keyMask, handler: .observe { _ in }, reset: { resets.append("p") }))
        subs.reverse()
        check("a reorder keeps the session", system.sessions.count == 1)
        guard case .reenable(let reordered)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a reordered disable notice names its subscribers", false)
        }
        check("a reorder names both subscribers", reordered.count == 2)
        system.live?.router.reenabled(reordered)
        drain()
        check("a reorder keeps each subscriber's reset, in the new order", resets == ["a", "p", "a"])
        subs.remove(probe)

        let swallowing = subs.add(NotchcastTap(
            switchID: "c", mask: NotchcastTapPolicy.mask(for: .otherMouseDown), handler: .synchronous { _, _ in .swallow }))
        check("a mask change restarts", system.sessions.count == 2 && !system.sessions[0].isRunning)
        check("a synchronous tap makes it active", system.live?.options == .defaultTap)
        let click = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero,
                            mouseButton: .center)!
        check("a synchronous tap swallows", system.live?.router.receive(type: .otherMouseDown, event: click) == .swallow)
        let stale = system.sessions[0].router
        check("a replaced session's router is inert", stale.receive(type: .tapDisabledByTimeout, event: key) == .pass)
        drain()
        check("no reset from a replaced session", resets == ["a", "p", "a"])

        let mouseMask = NotchcastTapPolicy.mask(for: .leftMouseDown)
        let mouse = subs.add(NotchcastTap(
            switchID: "m", mask: mouseMask, handler: .observe { _ in }, reset: { resets.append("m") }))
        guard case .reenable(let named)? = system.live?.router.receive(type: .tapDisabledByUserInput, event: key) else {
            return check("a disable notice names its subscribers", false)
        }
        system.live?.router.reenabled(named)
        let restarts = system.sessions.count
        subs.remove(mouse)
        drain()
        check("removing another mask restarts", system.sessions.count == restarts + 1)
        check("a restart before delivery keeps the survivor's reset", resets == ["a", "p", "a", "a"])

        guard case .reenable(let again)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a second disable notice names its subscribers", false)
        }
        system.live?.router.reenabled(again)
        let late = subs.add(NotchcastTap(
            switchID: "l", mask: keyMask, handler: .observe { _ in }, reset: { resets.append("late") }))
        drain()
        check("a subscriber added after the disable gets no reset", resets == ["a", "p", "a", "a", "a"])
        subs.remove(late)

        subs.remove(swallowing)
        subs.remove(first)
        check("the last removal ends the session", !hub.isRunning && hub.subscriberCount == 0)

        system.trusted = false
        let token = subs.add(NotchcastTap(switchID: "a", mask: keyMask, handler: .observe { _ in }))
        check("no session without trust", !hub.isRunning && !hub.isTrusted)
        system.trusted = true
        hub.refreshPermission()
        check("granting trust starts it", hub.isRunning && hub.isTrusted)
        subs.remove(token)
        staleActivation(system, subs)
        liveness(system, hub, subs)
    }

    /// An event and a reset queued for A, then A leaves and returns under the same id.
    static func staleActivation(_ system: FakeSystem, _ subs: Subscriptions) {
        var events = 0
        var resets = 0
        let keyMask = NotchcastTapPolicy.mask(for: .keyDown)
        let tap = NotchcastTap(
            switchID: "a", mask: keyMask, handler: .observe { _ in events += 1 }, reset: { resets += 1 })
        let returning = subs.add(tap)
        let keeper = subs.add(NotchcastTap(switchID: "b", mask: keyMask, handler: .observe { _ in }))
        let sessions = system.sessions.count
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true)!
        _ = system.live?.router.receive(type: .keyDown, event: key)
        guard case .reenable(let named)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a disable notice before a return names its subscribers", false)
        }
        system.live?.router.reenabled(named)
        subs.remove(returning)
        subs.insert(returning, tap, at: 0)
        drain()
        check("a return under the same id keeps the session", system.sessions.count == sessions)
        check("a returning tap gets no event queued for its last activation", events == 0)
        check("a returning tap gets no reset queued for its last activation", resets == 0)
        _ = system.live?.router.receive(type: .keyDown, event: key)
        guard case .reenable(let again)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a disable notice after a return names its subscribers", false)
        }
        system.live?.router.reenabled(again)
        drain()
        check("a returning tap gets its new activation's event and reset", events == 1 && resets == 1)
        subs.remove(keeper)
        subs.remove(returning)
    }

    /// MusicBlock's case: another add-on restarts the tap, the reinstall fails, its token stays.
    static func liveness(_ system: FakeSystem, _ hub: NotchcastTapHub, _ subs: Subscriptions) {
        let defaults = UserDefaults(suiteName: "nc-tap-test-liveness.\(UUID())")!
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: []),
            presenter: RecordingPresenter(), hub: hub,
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date() }, onTapsChanged: {})
        var resets: [String] = []
        let music = subs.add(NotchcastTap(
            switchID: "music", mask: NotchcastTapPolicy.mask(for: .keyDown), handler: .observe { _ in },
            reset: { resets.append("music live=\(context.isTapLive)") }))
        check("an installed tap is live", context.isTapLive)
        let other = subs.add(NotchcastTap(
            switchID: "other", mask: NotchcastTapPolicy.mask(for: .scrollWheel), handler: .observe { _ in }))
        let replaced = system.sessions[system.sessions.count - 2].router
        replaced.ended()
        drain()
        check("a session the hub replaced reports no loss", resets.isEmpty && context.isTapLive)
        system.sessions.last?.failInstall()
        drain()
        check("a failed reinstall is not live", !context.isTapLive && hub.isTrusted && hub.subscriberCount == 2)
        check("a failed reinstall resets the armed tap once", resets == ["music live=false"])
        hub.refreshPermission()
        check("refreshPermission retries the install", context.isTapLive && system.live === system.sessions.last)
        drain()
        check("a retry that installs adds no reset", resets == ["music live=false"])
        subs.remove(other)
        subs.remove(music)
    }

    /// Granting Accessibility posts nothing, so coming back to the app must retry the tap.
    static func trustMonitor() {
        let system = FakeSystem()
        let hub = system.makeHub()
        let center = NotificationCenter()
        var monitor: NotchcastTrustMonitor? = NotchcastTrustMonitor(hub: hub, center: center)
        system.trusted = false
        Subscriptions(hub).add(NotchcastTap(switchID: "a", mask: NotchcastTapPolicy.mask(for: .keyDown),
                                            handler: .observe { _ in }))
        check("an untrusted subscriber installs nothing", system.sessions.isEmpty && !hub.isTrusted)
        system.trusted = true
        drain()
        check("a grant alone changes nothing", system.sessions.isEmpty)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        drain()
        check("reactivating the app installs the tap", hub.isRunning && hub.isTrusted && system.sessions.count == 1)
        system.trusted = false
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        drain()
        check("a window coming forward rereads trust", !hub.isTrusted && !hub.isRunning)
        system.trusted = true
        monitor = nil
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        drain()
        check("a torn-down monitor stops listening", monitor == nil && !hub.isRunning)
        hub.stop()
    }
}
