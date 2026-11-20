// notchcast-hosted-only
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
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
// notchcast-reads: Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsView.swift
import AppKit
import CoreGraphics
import Foundation
import Synchronization

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
    }

    func stop() { ProbeLog.events.append("stop") }
}

enum NoticeAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "noticeMain", title: "Notice", subtitle: "", category: .music)]
    static let commands = [
        NotchcastCommand(slug: "notice-run", name: "Notice", symbol: "circle", switchID: "noticeMain") { context in
            context.presenter.post(
                IslandNotice(id: "musicBlock", text: "Couldn't Stop Apple Music Opening", isFailure: true), onTap: nil)
        },
    ]
}

enum ProbeAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "probeMain", title: "Probe", subtitle: "", category: .keyboardMouse),
        NotchcastSwitch(id: "probeChild", title: "Child", subtitle: "", category: .launcher,
                        dependencies: ["probeMain"]),
        NotchcastSwitch(id: "probeOrphan", title: "Orphan", subtitle: "", category: .music,
                        defaultEnabled: true, dependencies: ["absentSwitch"]),
        NotchcastSwitch(id: "probeLoopA", title: "A", subtitle: "", category: .music, dependencies: ["probeLoopB"]),
        NotchcastSwitch(id: "probeLoopB", title: "B", subtitle: "", category: .music, dependencies: ["probeLoopA"]),
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

/// Shipped command slugs on a probe, so the run path is proven without touching the clipboard or screen.
enum ShippedSlugAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "slugMain", title: "Slugs", subtitle: "", category: .launcher)]
    static let commands = ["generate-password", "screenshot-area"].map { slug in
        NotchcastCommand(slug: slug, name: slug, symbol: "circle", switchID: "slugMain") { _ in
            ProbeLog.events.append("ran " + slug)
        }
    }
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
        NotchcastSwitch(id: "order", title: "Order", subtitle: "", category: .launcher),
        NotchcastSwitch(id: "orderLate", title: "Late", subtitle: "", category: .launcher),
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
        NotchcastSwitch(id: "seqFirst", title: "First", subtitle: "", category: .launcher),
        NotchcastSwitch(id: "seqSecond", title: "Second", subtitle: "", category: .launcher),
    ]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { SequenceModule(context) }
}

@MainActor
final class LoggingModule: NotchcastModule {
    static var log: [String] = []
    let name: String
    let context: NotchcastContext?
    init(_ name: String, subscribingIn context: NotchcastContext? = nil) { (self.name, self.context) = (name, context) }
    func start() {
        Self.log.append("\(name) start")
        context?.subscribe(NotchcastTap(switchID: "recover", mask: NotchcastTapPolicy.mask(for: .keyDown),
                                        handler: .observe { _ in }))
    }
    func stop() { Self.log.append("\(name) stop") }
}

enum RecoveryAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "recover", title: "Recover", subtitle: "", category: .music)]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { LoggingModule("module") }
    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        LoggingModule("recovery", subscribingIn: context)
    }
}

@MainActor
final class HandoffRecovery: NotchcastModule {
    let name: String
    init(_ name: String) { self.name = name }
    func start() {}
    func stop() {}
}

/// Keeps its own context, as a real module does, so a test can call it after the switch detached it.
@MainActor
final class HandoffModule: NotchcastModule {
    static var built: [String: HandoffModule] = [:]
    let context: NotchcastContext
    init(_ name: String, _ context: NotchcastContext) {
        self.context = context
        Self.built[name] = self
    }
    var recoveryName: String? { context.recovery(HandoffRecovery.self)?.name }
    func start() {}
    func stop() {}
}

enum HandoffAddonA: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "handA", title: "A", subtitle: "", category: .power)]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { HandoffModule("A", context) }
    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? { HandoffRecovery("A") }
}

enum HandoffAddonB: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "handB", title: "B", subtitle: "", category: .power)]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { HandoffModule("B", context) }
    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? { HandoffRecovery("B") }
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
        mediaKeys()
        hotKeys()
        controller(defaults)
        hotKeyKeysRunTheirCommand(defaults)
        order(defaults)
        sequence(defaults)
        recovery(defaults)
        recoveryHandoff(defaults)
        islandPresenter(defaults)
        settingsTabs()
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

    static func hotKeyKeysRunTheirCommand(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let controller = NotchcastController(addons: [ShippedSlugAddon.self], defaults: defaults,
                                             hub: system.makeHub(), dictation: FakeDictation(),
                                             presenter: RecordingPresenter())
        controller.start()
        controller.preferences.set("slugMain", on: true)
        drain()
        let saved = ProbeLog.events
        for slug in ["generate-password", "screenshot-area"] {
            let key = "hotkey.command:nc-" + slug
            let action = HotKeyAction(entryID: String(key.dropFirst("hotkey.".count)))
            check("\(key) resolves to its command",
                  action == .notchcastCommand(entryID: "command:nc-" + slug) && action?.defaultsKey == key)
            ProbeLog.events = []
            let ran = action?.entryID.map(controller.run) == true
            check("\(key) runs exactly its command through the controller", ran && ProbeLog.events == ["ran " + slug])
        }
        ProbeLog.events = saved
        controller.stop()
    }

    static func controller(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let hub = system.makeHub()
        let presenter = RecordingPresenter()
        let controller = NotchcastController(addons: [ProbeAddon.self], defaults: defaults, hub: hub,
                                             dictation: FakeDictation(), presenter: presenter)
        var published: [[String]] = []
        controller.onCommandsChanged = { published.append($0.map(\.id)) }
        controller.start()
        check("nothing runs while off", ProbeLog.events.isEmpty && hub.subscriberCount == 0)
        check("no commands while off", controller.enabledCommands.isEmpty && !controller.run(entryID: "command:nc-probe-run"))

        controller.preferences.set("probeMain", on: true)
        drain()
        check("toggling on starts the module once", ProbeLog.events == ["start"])
        check("the module's own tap is live", hub.subscriberCount == 1 && hub.isRunning)
        check("its command is published", published == [["command:nc-probe-run"]])
        check("its command runs", controller.run(entryID: "command:nc-probe-run"))
        check("the notice reaches the presenter", presenter.log == ["post probe Probe ran"])
        check("an unknown id falls through", !controller.run(entryID: "command:nc-nope"))
        check("the context finds its module", controller.context(forSwitch: "probeMain")?.module(ProbeModule.self) != nil)
        let probe = controller.enabledCommands
        controller.preferences.setShowsInLauncher("command:nc-probe-run", false)
        check("Show in launcher off leaves the launcher list, keeping the command",
              published.count == 2 && controller.launcherCommands(probe).isEmpty
                  && controller.run(entryID: "command:nc-probe-run"))
        controller.preferences.setShowsInLauncher("command:nc-probe-run", true)
        check("Show in launcher on lists it again", published.count == 3 && controller.launcherCommands(probe).count == 1)
        let probeContext = controller.context(forSwitch: "probeMain")
        probeContext?.setUnavailable(["command:nc-probe-run"])
        check("a command its module marks unavailable leaves the launcher, keeping its hotkey",
              published.count == 4 && controller.launcherCommands(probe).isEmpty && controller.enabledCommands.count == 1)
        probeContext?.setUnavailable(["command:nc-probe-run"])
        check("marking it unavailable again publishes nothing", published.count == 4)
        probeContext?.setUnavailable([])
        check("available again lists it again", published.count == 5 && controller.launcherCommands(probe).count == 1)

        controller.preferences.set("probeChild", on: true)
        drain()
        check("a declared tap follows its switch", hub.subscriberCount == 2)
        check("a second switch does not restart the module", ProbeLog.events == ["start"])

        probeContext?.setUnavailable(["command:nc-probe-run"])
        controller.preferences.set("probeMain", on: false)
        drain()
        check("toggling off stops the module", ProbeLog.events == ["start", "stop"])
        check("a stopped module's unavailable commands are cleared", probeContext?.unavailableCommands.isEmpty == true)
        check("its taps and dependents' taps go", hub.subscriberCount == 0 && !hub.isRunning)
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
                                             dictation: FakeDictation(), presenter: RecordingPresenter())
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
                                             dictation: FakeDictation(), presenter: RecordingPresenter())
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

    /// A recovery runs whatever the switch says, so a dirty journal is repaired with the add-on off.
    static func recovery(_ defaults: UserDefaults) {
        ProbeLog.events = []
        LoggingModule.log = []
        let system = FakeSystem()
        let hub = system.makeHub()
        func make() -> NotchcastController {
            NotchcastController(addons: [ProbeAddon.self, RecoveryAddon.self], defaults: defaults, hub: hub,
                                dictation: FakeDictation(), presenter: RecordingPresenter())
        }
        let off = make()
        off.start()
        off.start()
        check("the recovery starts once with its switch off", LoggingModule.log == ["recovery start"])
        check("a default-nil add-on builds nothing", ProbeLog.events.isEmpty && hub.subscriberCount == 0)
        off.stop()
        check("stop stops the recovery", LoggingModule.log == ["recovery start", "recovery stop"])
        off.preferences.set("recover", on: true)
        drain()
        check("a stopped controller builds no recovery", LoggingModule.log.count == 2)

        LoggingModule.log = []
        let on = make()
        on.start()
        check("the recovery starts before the switch's module", LoggingModule.log == ["recovery start", "module start"])
        check("the recovery's tap is live while its switch is on", hub.subscriberCount == 1)
        on.preferences.set("recover", on: false)
        drain()
        on.preferences.set("recover", on: true)
        drain()
        check("the recovery's tap survives its add-on going off and on", hub.subscriberCount == 1)
        check("off and on leave the recovery running",
              LoggingModule.log == ["recovery start", "module start", "module stop", "module start"])
        on.stop()
        check("stop ends the module, then the recovery",
              LoggingModule.log.suffix(2) == ["module stop", "recovery stop"])
        check("stop clears the recovery's tap", hub.subscriberCount == 0 && !hub.isRunning)
        on.start()
        check("a restart builds a fresh recovery", LoggingModule.log.suffix(2) == ["recovery start", "module start"])
        check("stop cleared the old recovery's tap, so only the fresh one is live", hub.subscriberCount == 1)
        on.stop()
        check("the default-nil add-on stayed untouched throughout", ProbeLog.events.isEmpty)
    }

    /// A module hands work to its own add-on's recovery, which outlives the switch going off.
    static func recoveryHandoff(_ defaults: UserDefaults) {
        HandoffModule.built = [:]
        let system = FakeSystem()
        let controller = NotchcastController(addons: [ProbeAddon.self, HandoffAddonA.self, HandoffAddonB.self],
                                             defaults: defaults, hub: system.makeHub(), dictation: FakeDictation(), presenter: RecordingPresenter())
        controller.preferences.set("handA", on: true)
        controller.preferences.set("handB", on: true)
        controller.start()
        let a = HandoffModule.built["A"], b = HandoffModule.built["B"]
        check("a module reaches its add-on's recovery after start", a?.recoveryName == "A")
        check("add-on B reaches its own recovery, never A's", b?.recoveryName == "B")
        check("an add-on without a recovery reaches none",
              controller.context(forSwitch: "probeMain")?.recovery(HandoffRecovery.self) == nil)
        controller.preferences.set("handA", on: false)
        drain()
        check("switching A off detaches its module", controller.context(forSwitch: "handA")?.module == nil)
        check("a detached module still reaches its recovery while the controller runs", a?.recoveryName == "A")
        controller.stop()
        check("no recovery is reachable after controller stop", a?.recoveryName == nil && b?.recoveryName == nil)
        controller.preferences.set("handA", on: false)
        controller.preferences.set("handB", on: false)
    }

    /// NotchcastCore needs AppCore, which no harness builds, so its presenter line is read as text.
    static func islandPresenter(_ defaults: UserDefaults) {
        let system = FakeSystem()
        let presenter = RecordingPresenter()
        let controller = NotchcastController(addons: [NoticeAddon.self], defaults: defaults,
                                             hub: system.makeHub(),
                                             dictation: FakeDictation(), presenter: presenter)
        controller.start()
        controller.preferences.set("noticeMain", on: true)
        drain()
        check("an add-on notice runs", controller.run(entryID: "command:nc-notice-run"))
        check("an add-on notice reaches the controller's presenter",
              presenter.log == ["post musicBlock Couldn't Stop Apple Music Opening"])
        controller.stop()
        let path = "Tinycast/Features/Notchcast/NotchcastCore.swift"
        let core = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let calls = core.components(separatedBy: "NotchcastController(").dropFirst()
        check("NotchcastCore builds one controller", calls.count == 1)
        func arguments(_ tail: String) -> String {
            var depth = 1
            return String(tail.prefix { depth += $0 == "(" ? 1 : $0 == ")" ? -1 : 0; return depth > 0 })
        }
        check("NotchcastCore hands the controller the island presenter",
              calls.allSatisfy {
                  arguments($0).components(separatedBy: ",").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      == "presenter: core.islandPresenter" }
              })
        check("NotchcastCore hands the controller stock Dictation",
              calls.allSatisfy { $0.contains("dictation: NotchcastDictationBridge(core: core)") })
        check("nc command entries are owned by their add-on tab, never gated by stock Commands",
              core.contains("owner: .notchcast(tabs[$0.switchID]"))
        let viewPath = "Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsView.swift"
        let view = FileManager.default.contents(atPath: viewPath).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("each add-on switch draws its commands' alias and hotkey fields",
              view.contains("AliasField(key: command.id, name: command.name)")
                && view.contains("ShortcutRecorder(action: .notchcastCommand(entryID: command.id))"))
        check("each add-on command draws its own Show in launcher checkbox",
              view.contains("preferences.setShowsInLauncher(command.id, $0)"))
        check("that checkbox says what it does on screen, not only to VoiceOver",
              view.contains("Toggle(\"Show in launcher\", isOn:") && !view.contains(".labelsHidden()"))
    }

    /// The Notchcast sidebar section: which tab holds which category, which tabs show, and their links.
    static func settingsTabs() {
        check("each tab holds its categories",
              NotchcastPane.allCases.map(\.categories)
                == [[], [.agents], [.keyboardMouse], [.displaySound, .music], [.capture], [.launcher], [.filesDownloads],
                   [.power], [.macTweaks]])
        check("no category sits in two tabs", NotchcastCategory.allCases.allSatisfy { category in
            NotchcastPane.allCases.filter { $0.categories.contains(category) }.count <= 1
        })
        let placed = Set(NotchcastPane.allCases.flatMap(\.categories))
        check("a placed category resolves to the tab that holds it",
              placed.allSatisfy { NotchcastPane.holding($0).categories.contains($0) })
        check("a category with no tab yet shows nowhere",
              NotchcastPane.shown(registered: [.notices, .betweenMacs]) == [.island])
        check("Low disk warning and iPhone backup land in their own tabs",
              NotchcastPane.shown(registered: [.macTweaks, .power]) == [.island, .power, .macTweaks])
        check("with no add-on only Island shows", NotchcastPane.shown(registered: []) == [.island])
        check("an add-on tab shows once one of its categories has a switch",
              NotchcastPane.shown(registered: [.music]) == [.island, .displaySound]
                && NotchcastPane.shown(registered: [.displaySound]) == [.island, .displaySound])
        check("Screenshots lands in Capture, after Display & Sound",
              NotchcastPane.holding(.capture) == .capture
                && NotchcastPane.shown(registered: [.launcher, .capture, .music])
                == [.island, .displaySound, .capture, .launcher])
        NotchcastPane.install(Set(NotchcastCategory.allCases))
        check("the section lists every tab once all are filled",
              SettingsSection.notchcast.tabs == NotchcastPane.allCases.map(SettingsTab.notchcast))
        let slugs = SettingsTab.allCases.map(\.slug)
        check("settings slugs are unique", Set(slugs).count == slugs.count)
        check("each tab opens from its deep link",
              NotchcastPane.allCases.allSatisfy { SettingsTab(slug: $0.slug) == .notchcast($0) })
        check("the old notchcast slug opens nothing", SettingsTab(slug: "notchcast") == nil)
        NotchcastPane.install([])
        check("a hidden tab's deep link opens nothing", SettingsTab(slug: "notchcast-downloads") == nil)
        check("the Capture tab opens from its own link", NotchcastPane.capture.slug == "notchcast-capture")
        check("Island's deep link always opens", SettingsTab(slug: "notchcast-island") == .notchcast(.island))
    }
}
