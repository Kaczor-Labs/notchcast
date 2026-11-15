// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift
import AppKit
import CoreGraphics
import Foundation
import Synchronization

@MainActor
final class RecordingPresenter: IslandPresenting {
    var log: [String] = []

    func showLevel(_ level: IslandLevel) { log.append("level \(level.source) \(level.value)") }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { log.append("post \(notice.id) \(notice.text)") }
    func end(notice id: String) { log.append("end \(id)") }
    func setStatus(_ status: IslandStatus?, for id: String) { log.append("status \(id)") }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        log.append("menu \(owner) \(rows.count)")
    }
}

/// Stands in for NotchcastTapThread: no real tap is ever created on this Mac.
final class FakeSession: NotchcastTapSession {
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
final class FakeSystem {
    var trusted = true
    var sessions: [FakeSession] = []
    var live: FakeSession? { sessions.last.flatMap { $0.isRunning ? $0 : nil } }

    func makeHub() -> NotchcastTapHub {
        NotchcastTapHub(syntheticTag: syntheticTag, isTrusted: { [unowned self] in trusted }) { [unowned self] in
            let session = FakeSession($0)
            sessions.append(session)
            return session
        }
    }
}

let syntheticTag: Int64 = 0x7E57

@MainActor
enum ProbeLog {
    static var events: [String] = []
}

@MainActor
final class ProbeModule: NotchcastModule {
    let context: NotchcastContext
    var token: UUID?

    init(_ context: NotchcastContext) { self.context = context }

    func start() {
        ProbeLog.events.append("start")
        token = context.subscribe(
            NotchcastTap(switchID: "probeMain", mask: NotchcastTapPolicy.mask(for: .leftMouseDown),
                         handler: .observe { _ in }))
        context.handleLauncherDigit { digit, query, entryRows in
            query.isEmpty || digit > entryRows.count ? nil : entryRows[digit - 1]
        }
    }

    func stop() { ProbeLog.events.append("stop") }
}

enum ProbeAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "probeMain", title: "Probe", subtitle: "", category: .capture),
        NotchcastSwitch(id: "probeChild", title: "Child", subtitle: "", category: .macTweaks,
                        dependencies: ["probeMain"]),
        NotchcastSwitch(id: "probeOrphan", title: "Orphan", subtitle: "", category: .notices,
                        defaultEnabled: true, dependencies: ["absentSwitch"]),
        NotchcastSwitch(id: "probeLoopA", title: "A", subtitle: "", category: .power, dependencies: ["probeLoopB"]),
        NotchcastSwitch(id: "probeLoopB", title: "B", subtitle: "", category: .power, dependencies: ["probeLoopA"]),
    ]
    static let commands = [
        NotchcastCommand(slug: "probe-run", name: "Probe", symbol: "circle", switchID: "probeMain") { context in
            context.presenter.post(IslandNotice(id: "probe", text: "Probe ran"), onTap: nil)
        },
    ]
    static let taps = [
        NotchcastTap(switchID: "probeChild", mask: NotchcastTapPolicy.mask(for: .keyDown), handler: .observe { _ in }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { ProbeModule(context) }
}

final class OrderLog: Sendable {
    static let shared = OrderLog()
    private let state = Mutex<(entries: [String], value: Int64)>(([], 0))
    var all: [String] { state.withLock { $0.entries } }
    func clear() { state.withLock { $0 = ([], 0) } }
    func record(_ label: String, writing value: Int64) {
        state.withLock {
            $0.entries.append("\(label)\($0.value)")
            $0.value = value
        }
    }
}

/// Each handler logs the value the previous one wrote, so the log shows the run order.
func chainedTap(_ label: String, _ index: Int64, type: CGEventType, switchID: String = "order") -> NotchcastTap {
    NotchcastTap(switchID: switchID, mask: NotchcastTapPolicy.mask(for: type), handler: .synchronous { _, _ in
        OrderLog.shared.record(label, writing: index + 1)
        return .pass
    })
}

@MainActor
final class OrderModule: NotchcastModule {
    let context: NotchcastContext
    init(_ context: NotchcastContext) { self.context = context }
    func start() {
        for index in 0..<6 { context.subscribe(chainedTap("w", Int64(index), type: .keyDown, switchID: "orderLate")) }
    }
    func stop() {}
}

enum OrderAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "order", title: "Order", subtitle: "", category: .macTweaks),
        NotchcastSwitch(id: "orderLate", title: "Late", subtitle: "", category: .macTweaks),
    ]
    static let taps = (0..<6).map { chainedTap("d", Int64($0), type: .otherMouseDown) }
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { OrderModule(context) }
}

@main
@MainActor
struct NotchcastCoreTest {
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
        let suite = "nc-core-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        preferences(UserDefaults(suiteName: suite + ".prefs")!)
        UserDefaults.standard.removePersistentDomain(forName: suite + ".prefs")
        hub()
        mediaKeys()
        hotKeys()
        controller(defaults)
        order(defaults)
        print(failures == 0 ? "PASS NotchcastCoreTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static func preferences(_ defaults: UserDefaults) {
        let prefs = NotchcastPreferences(defaults: defaults, switches: ProbeAddon.switches)
        check("suite name keeps v1's", NotchcastPreferences.suiteName(bundleID: "app.x") == "app.x.notchcast")
        check("off by default", !prefs.isOn("probeMain"))
        prefs.set("probeMain", on: false)
        check("an unchanged value is not written", defaults.object(forKey: "probeMain") == nil)
        prefs.set("probeMain", on: true)
        check("a change is written under the id", defaults.bool(forKey: "probeMain"))
        prefs.set("undeclared", on: true)
        check("an undeclared id is never written", defaults.object(forKey: "undeclared") == nil)
        check("undeclared reads off", !prefs.isOn("undeclared") && !prefs.isEnabled("undeclared"))
        check("default on reads on", prefs.isOn("probeOrphan"))
        check("an absent dependency counts as off", !prefs.isEnabled("probeOrphan"))
        prefs.set("probeChild", on: true)
        check("a dependency that is on enables", prefs.isEnabled("probeChild"))
        prefs.set("probeMain", on: false)
        check("a dependency that is off disables", prefs.isOn("probeChild") && !prefs.isEnabled("probeChild"))
        prefs.set("probeLoopA", on: true)
        prefs.set("probeLoopB", on: true)
        check("a dependency cycle reads off", !prefs.isEnabled("probeLoopA"))
        let reread = NotchcastPreferences(defaults: defaults, switches: ProbeAddon.switches)
        check("stored values load", reread.isOn("probeChild") && !reread.isOn("probeMain"))
    }

    static func hub() {
        let system = FakeSystem()
        let hub = system.makeHub()
        let keyMask = NotchcastTapPolicy.mask(for: .keyDown)
        check("no session without subscribers", system.sessions.isEmpty && !hub.isRunning)

        var seen: [Int64] = []
        var resets: [String] = []
        let first = hub.subscribe(NotchcastTap(
            switchID: "a", mask: keyMask, handler: .observe { seen.append($0.keyCode) }, reset: { resets.append("a") }))
        let second = hub.subscribe(NotchcastTap(
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

        let notice = system.live?.router.receive(type: .tapDisabledByTimeout, event: key)
        check("a disable notice re-enables, naming its subscribers", notice == .reenable([first, second]))
        drain()
        check("no reset before the tap is re-enabled", resets.isEmpty)
        system.live?.router.reenabled([first, second])
        hub.remove(second)
        drain()
        check("reset reaches live subscribers only, once", resets == ["a"])
        check("same mask keeps the session", system.sessions.count == 1)

        let swallowing = hub.subscribe(NotchcastTap(
            switchID: "c", mask: NotchcastTapPolicy.mask(for: .otherMouseDown), handler: .synchronous { _, _ in .swallow }))
        check("a mask change restarts", system.sessions.count == 2 && !system.sessions[0].isRunning)
        check("a synchronous tap makes it active", system.live?.options == .defaultTap)
        let click = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero,
                            mouseButton: .center)!
        check("a synchronous tap swallows", system.live?.router.receive(type: .otherMouseDown, event: click) == .swallow)
        let stale = system.sessions[0].router
        check("a replaced session's router is inert", stale.receive(type: .tapDisabledByTimeout, event: key) == .pass)
        drain()
        check("no reset from a replaced session", resets == ["a"])

        let mouseMask = NotchcastTapPolicy.mask(for: .leftMouseDown)
        let mouse = hub.subscribe(NotchcastTap(
            switchID: "m", mask: mouseMask, handler: .observe { _ in }, reset: { resets.append("m") }))
        guard case .reenable(let named)? = system.live?.router.receive(type: .tapDisabledByUserInput, event: key) else {
            return check("a disable notice names its subscribers", false)
        }
        system.live?.router.reenabled(named)
        let restarts = system.sessions.count
        hub.remove(mouse)
        drain()
        check("removing another mask restarts", system.sessions.count == restarts + 1)
        check("a restart before delivery keeps the survivor's reset", resets == ["a", "a"])

        guard case .reenable(let again)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a second disable notice names its subscribers", false)
        }
        system.live?.router.reenabled(again)
        let late = hub.subscribe(NotchcastTap(
            switchID: "l", mask: keyMask, handler: .observe { _ in }, reset: { resets.append("late") }))
        drain()
        check("a subscriber added after the disable gets no reset", resets == ["a", "a", "a"])
        hub.remove(late)

        hub.remove(swallowing)
        hub.remove(first)
        check("the last removal ends the session", !hub.isRunning && hub.subscriberCount == 0)

        system.trusted = false
        let token = hub.subscribe(NotchcastTap(switchID: "a", mask: keyMask, handler: .observe { _ in }))
        check("no session without trust", !hub.isRunning && !hub.isTrusted)
        system.trusted = true
        hub.refreshPermission()
        check("granting trust starts it", hub.isRunning && hub.isTrusted)
        hub.remove(token)
    }

    static func mediaKeys() {
        let down = NotchcastMediaKey(subtype: 8, data1: (NotchcastMediaKey.Key.soundUp.rawValue << 16) | 0x0A00)
        check("volume up down", down?.key == .soundUp && down?.isDown == true && down?.isRepeat == false)
        let up = NotchcastMediaKey(subtype: 8, data1: (3 << 16) | 0x0B01)
        check("brightness down up, repeat", up?.key == .brightnessDown && up?.isDown == false && up?.isRepeat == true)
        check("other subtypes are no media key", NotchcastMediaKey(subtype: 7, data1: 0x0A00) == nil)
        check("an unknown state is no media key", NotchcastMediaKey(subtype: 8, data1: 0x0C00) == nil)
        check("an unknown code keeps its number", NotchcastMediaKey(subtype: 8, data1: (99 << 16) | 0x0A00)?.key == nil)
        let ns = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: (NotchcastMediaKey.Key.play.rawValue << 16) | 0x0A00, data2: -1)
        let event = ns?.cgEvent
        check("systemDefined is type 14", event?.type.rawValue == NotchcastMediaKey.eventType)
        let decoded = event.flatMap { NotchcastTapEvent.mediaKey(type: $0.type, event: $0) }
        check("a real systemDefined event decodes", decoded?.key == .play && decoded?.isDown == true)
        check("the tap bit for type 14", NotchcastTapPolicy.mask(rawType: 14) == 1 << 14)
        check("no bit past the mask width", NotchcastTapPolicy.mask(rawType: 64) == 0)
    }

    static func hotKeys() {
        for slug in ["screenshot-area", "screenshot-display"] {
            let entryID = NotchcastCommand.idPrefix + slug
            let action = HotKeyAction(entryID: entryID)
            check("\(slug) maps", action == .notchcastCommand(entryID: entryID))
            check("\(slug) key", action?.defaultsKey == "hotkey.command:nc-\(slug)")
            check("\(slug) round-trips", action?.entryID == entryID)
        }
        check("a stock command is untouched", HotKeyAction(entryID: "command:nc") == nil)
    }

    static func controller(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let hub = system.makeHub()
        let presenter = RecordingPresenter()
        let controller = NotchcastController(addons: [ProbeAddon.self], defaults: defaults, hub: hub,
                                             presenter: presenter)
        var published: [[String]] = []
        controller.onCommandsChanged = { published.append($0.map(\.id)) }
        controller.start()
        check("nothing runs while off", ProbeLog.events.isEmpty && hub.subscriberCount == 0)
        check("no digit row while off", controller.launcherRow(digit: 1, query: "sa", entryRows: [2, 5]) == nil)
        check("no commands while off", controller.enabledCommands.isEmpty && !controller.run(entryID: "command:nc-probe-run"))

        controller.preferences.set("probeMain", on: true)
        drain()
        check("toggling on starts the module once", ProbeLog.events == ["start"])
        check("the module's own tap is live", hub.subscriberCount == 1 && hub.isRunning)
        check("its command is published", published == [["command:nc-probe-run"]])
        check("its command runs", controller.run(entryID: "command:nc-probe-run"))
        check("the notice reaches the presenter", presenter.log == ["post probe Probe ran"])
        check("an unknown id falls through", !controller.run(entryID: "command:nc-nope"))
        check("a digit maps to its entry row", controller.launcherRow(digit: 2, query: "sa", entryRows: [2, 5]) == 5)
        check("a declined digit falls through", controller.launcherRow(digit: 3, query: "sa", entryRows: [2, 5]) == nil)
        check("the context finds its module", controller.context(forSwitch: "probeMain")?.module(ProbeModule.self) != nil)

        controller.preferences.set("probeChild", on: true)
        drain()
        check("a declared tap follows its switch", hub.subscriberCount == 2)
        check("a second switch does not restart the module", ProbeLog.events == ["start"])

        controller.preferences.set("probeMain", on: false)
        drain()
        check("toggling off stops the module", ProbeLog.events == ["start", "stop"])
        check("its taps and dependents' taps go", hub.subscriberCount == 0 && !hub.isRunning)
        check("a stopped module's digit handler is gone",
              controller.launcherRow(digit: 1, query: "sa", entryRows: [2, 5]) == nil)
        check("its command is withdrawn", published.last == [] && controller.enabledCommands.isEmpty)
        check("a withdrawn command no longer runs", !controller.run(entryID: "command:nc-probe-run"))

        controller.preferences.set("probeMain", on: true)
        drain()
        check("toggling on again starts a fresh module", ProbeLog.events == ["start", "stop", "start"])
        check("both taps return", hub.subscriberCount == 2)

        controller.stop()
        check("stop stops the module", ProbeLog.events.last == "stop" && hub.subscriberCount == 0)
        controller.preferences.set("probeMain", on: false)
        drain()
        check("a stopped controller ignores toggles", ProbeLog.events.count == 4)
    }

    static func order(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let hub = system.makeHub()
        let controller = NotchcastController(addons: [OrderAddon.self], defaults: defaults, hub: hub,
                                             presenter: RecordingPresenter())
        controller.start()
        controller.preferences.set("order", on: true)
        drain()
        check("subscriptions wait for their switch", hub.subscriberCount == 6)
        controller.preferences.set("orderLate", on: true)
        drain()
        check("all twelve chained taps are live", hub.subscriberCount == 12)
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true)!
        _ = system.live?.router.receive(type: .keyDown, event: key)
        check("subscribed taps run in order, each seeing the last one's change",
              OrderLog.shared.all == (0..<6).map { "w\($0)" })
        OrderLog.shared.clear()
        let click = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero,
                            mouseButton: .center)!
        _ = system.live?.router.receive(type: .otherMouseDown, event: click)
        check("declared taps run in declaration order", OrderLog.shared.all == (0..<6).map { "d\($0)" })
        controller.stop()
    }
}
