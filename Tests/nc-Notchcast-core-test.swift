// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
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

    /// What NotchcastTapThread does when CGEvent.tapCreate fails: the session ends on its own.
    func failInstall() {
        isRunning = false
        router.ended()
    }
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

/// Drives the hub as the controller does: the whole ordered list on every change.
@MainActor
final class Subscriptions {
    let hub: NotchcastTapHub
    private(set) var list: [(id: UUID, tap: NotchcastTap)] = []

    init(_ hub: NotchcastTapHub) { self.hub = hub }

    @discardableResult
    func add(_ tap: NotchcastTap) -> UUID {
        let id = UUID()
        list.append((id, tap))
        hub.setSubscribers(list)
        return id
    }

    func remove(_ id: UUID) {
        list.removeAll { $0.id == id }
        hub.setSubscribers(list)
    }

    func reverse() {
        list.reverse()
        hub.setSubscribers(list)
    }
}

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

/// Subscribes first then second, each under its own switch, so either can be enabled before the other.
@MainActor
final class SequenceModule: NotchcastModule {
    let context: NotchcastContext
    init(_ context: NotchcastContext) { self.context = context }
    func start() {
        context.subscribe(chainedTap("first", 0, type: .keyUp, switchID: "seqFirst"))
        context.subscribe(chainedTap("second", 1, type: .keyUp, switchID: "seqSecond"))
    }
    func stop() {}
}

enum SequenceAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "seqFirst", title: "First", subtitle: "", category: .macTweaks),
        NotchcastSwitch(id: "seqSecond", title: "Second", subtitle: "", category: .macTweaks),
    ]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { SequenceModule(context) }
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
        sequence(defaults)
        trustMonitor()
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

        let notice = system.live?.router.receive(type: .tapDisabledByTimeout, event: key)
        check("a disable notice re-enables, naming its subscribers", notice == .reenable([first, second]))
        drain()
        check("no reset before the tap is re-enabled", resets.isEmpty)
        system.live?.router.reenabled([first, second])
        subs.remove(second)
        drain()
        check("reset reaches live subscribers only, once", resets == ["a"])
        check("same mask keeps the session", system.sessions.count == 1)
        let probe = subs.add(NotchcastTap(switchID: "p", mask: keyMask, handler: .observe { _ in }))
        subs.reverse()
        check("a reorder keeps the session", system.sessions.count == 1)
        guard case .reenable(let reordered)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a reordered disable notice names its subscribers", false)
        }
        check("a reorder keeps ids and takes the new order", reordered == [probe, first])
        system.live?.router.reenabled(reordered)
        drain()
        check("a reorder keeps each subscriber's reset", resets == ["a", "a"])
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
        check("no reset from a replaced session", resets == ["a", "a"])

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
        check("a restart before delivery keeps the survivor's reset", resets == ["a", "a", "a"])

        guard case .reenable(let again)? = system.live?.router.receive(type: .tapDisabledByTimeout, event: key) else {
            return check("a second disable notice names its subscribers", false)
        }
        system.live?.router.reenabled(again)
        let late = subs.add(NotchcastTap(
            switchID: "l", mask: keyMask, handler: .observe { _ in }, reset: { resets.append("late") }))
        drain()
        check("a subscriber added after the disable gets no reset", resets == ["a", "a", "a", "a"])
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
        liveness(system, hub, subs)
    }

    /// MusicBlock's case: another add-on restarts the tap, the reinstall fails, its token stays.
    static func liveness(_ system: FakeSystem, _ hub: NotchcastTapHub, _ subs: Subscriptions) {
        let defaults = UserDefaults(suiteName: "nc-core-test-liveness.\(UUID())")!
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: []),
            presenter: RecordingPresenter(), hub: hub, now: { Date() }, onTapsChanged: {})
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

    /// A tap enabled late still runs in subscription order, through re-enables too.
    static func sequence(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let hub = system.makeHub()
        let controller = NotchcastController(addons: [SequenceAddon.self], defaults: defaults, hub: hub,
                                             presenter: RecordingPresenter())
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: false)!
        func run() -> [String] {
            OrderLog.shared.clear()
            _ = system.live?.router.receive(type: .keyUp, event: key)
            return OrderLog.shared.all
        }
        controller.start()
        controller.preferences.set("seqSecond", on: true)
        drain()
        check("the second switch alone runs the second tap", run() == ["second0"])
        controller.preferences.set("seqFirst", on: true)
        drain()
        check("enabling the first later still runs it first", run() == ["first0", "second1"])
        controller.preferences.set("seqFirst", on: false)
        drain()
        check("disabling the first leaves the second", run() == ["second0"])
        controller.preferences.set("seqFirst", on: true)
        drain()
        check("re-enabling the first puts it back in front", run() == ["first0", "second1"])
        controller.preferences.set("seqSecond", on: false)
        controller.preferences.set("seqSecond", on: true)
        drain()
        check("re-enabling the second keeps it behind", run() == ["first0", "second1"])
        controller.stop()
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
