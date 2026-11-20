// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Notchcast/Accessories/AccessoriesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Accessories/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Accessories/Service/AccessoriesModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import SwiftUI

// The shipped readers, Bluetooth watcher, banner hider and settings view are left out: these stand in.

struct AccessoriesSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

final class AccessoriesWatcher {
    private let cancel: () -> Void
    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }
    deinit { cancel() }
}

/// The system as the live readers would report it, and what the module handed back.
@MainActor
final class FakeSystem {
    var hid: [AccessoryBattery] = []
    var profiler: [AccessoryBattery] = []
    var profilerReads = 0
    var connection: (@MainActor @Sendable (AccessoryConnectionEvent) -> Void)?
    var bannerNames: [String: Date] = [:]
    var live = 0
    var now = Date(timeIntervalSinceReferenceDate: 0)
}

@MainActor let system = FakeSystem()

extension AccessoriesModule {
    static func readHID() async -> [AccessoryBattery] { system.hid }

    static func readProfiler() async -> [AccessoryBattery] {
        system.profilerReads += 1
        return system.profiler
    }

    static func watchConnections(
        _ handler: @escaping @MainActor @Sendable (AccessoryConnectionEvent) -> Void
    ) -> AccessoriesWatcher? {
        system.connection = handler
        system.live += 1
        return AccessoriesWatcher { Task { @MainActor in system.live -= 1 } }
    }

    static func watchBanners(_ defaults: UserDefaults) -> AccessoryBannerHandle? {
        AccessoryBannerHandle(
            watcher: AccessoriesWatcher {},
            setNames: { names in Task { @MainActor in system.bannerNames = names } },
            refresh: {})
    }
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
    var taps: [String: @MainActor () -> Void] = [:]
    var ends: [String] = []
    var page: IslandPage?
    var pageAction: (@MainActor (String) -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?
    var shown: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps[notice.id] = onTap
    }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        precondition(id == AccessoryPage.id, "one page id")
        self.page = page
        pageAction = onAction
    }
    func watchPages(id: String, onChange: (@MainActor (Bool) -> Void)?) { watcher = onChange }
    func showPage(id: String) { shown.append(id) }
}

@MainActor
final class Rig {
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController

    init(suite: String, on: Bool) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(on, forKey: "accessoryNotices")
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [AccessoriesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { system.now })
        controller.start()
    }

    var context: NotchcastContext { controller.context(forSwitch: "accessoryNotices")! }

    /// A module with no poll loop: a poll sleep ends it, the short wait after a connection returns at once.
    func module() -> AccessoriesModule {
        AccessoriesModule(context: context) { duration in
            if duration == AccessoriesModule.poll { throw CancellationError() }
        }
    }

    var texts: [String] { presenter.posts.map(\.text) }
}

func device(_ name: String, _ percent: Int, _ kind: AccessoryKind = .mouse,
            parts: [AccessoryBattery.Part] = []) -> AccessoryBattery {
    AccessoryBattery(name: name, percent: percent, kind: kind, parts: parts)
}

func settle() async { for _ in 0..<20 { await Task.yield() } }

@main
@MainActor
enum AccessoriesModuleTests {
    static func main() async {
        descriptor()
        readings()
        lowWatch()
        connections()
        policy()
        page()
        await module()
        await switches()
        print("PASS nc-Accessories-module-test")
    }

    static func descriptor() {
        let only = AccessoriesAddon.switches
        precondition(only.map(\.id) == ["accessoryNotices"], "v1 switch id")
        precondition(only[0].defaultEnabled == false, "off by default")
        precondition(only[0].category == .notices, "Notices category")
        precondition(NotchcastPane.holding(.notices) == .notices, "in the Notices tab")
        precondition(AccessoriesAddon.settings.map(\.switchID) == ["accessoryNotices"], "the checkboxes sit under it")
        precondition(AccessoryLowWatch.threshold == 20 && AccessoryLowWatch.recovery == 25, "Vorssaint's 20 and 25")
    }

    static func readings() {
        let mouse = AccessoryReadings.hid(["Product": "Magic Mouse", "BatteryPercent": 55])
        precondition(mouse == device("Magic Mouse", 55), "a HID service with a name and a level")
        precondition(AccessoryReadings.hid(["Product": "Keyboard", "BatteryPercent": 40, "Built-In": true]) == nil,
                     "a built-in device is not an accessory")
        precondition(AccessoryReadings.hid(["Product": "Pointer"]) == nil, "no level, no entry")
        precondition(AccessoryReadings.hid(["Product": "Pointer", "BatteryPercent": 140]) == nil, "a level past 100 is a lie")
        precondition(AccessoryReadings.hid(["Product": "MX", "BatteryPercent": "62 %", "PrimaryUsagePage": 1,
                                            "PrimaryUsage": 2])?.kind == .mouse, "the HID usage names a pointer")

        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Kim's AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"75%",
            "device_batteryLevelCase":"40%","device_minorType":"Headphones"}},
          {"Magic Keyboard":{"device_batteryLevelMain":"90%"}},
          {"Speaker":{"device_minorType":"Speaker"}}]}]}
        """
        let profiled = AccessoryReadings.profiler(Data(json.utf8))
        let pods = profiled.first { $0.name == "Kim's AirPods Pro" }
        precondition(pods?.percent == 40 && pods?.kind == .audio, "AirPods count as their lowest part")
        precondition(pods?.parts == [.init(name: .left, percent: 80), .init(name: .right, percent: 75),
                                     .init(name: .batteryCase, percent: 40)], "with left, right and case kept")
        precondition(profiled.first { $0.name == "Magic Keyboard" }?.parts == [], "a main level has no parts")
        precondition(profiled.count == 2, "a device with no level is left out")
        precondition(AccessoryReadings.profiler(Data("nope".utf8)).isEmpty, "unreadable output reads as nothing")

        let merged = AccessoryReadings.merge(hid: [device("Magic Keyboard", 88, .keyboard)], profiler: profiled)
        precondition(merged.map(\.name) == ["Kim's AirPods Pro", "Magic Keyboard"], "one per name, lowest first")
        precondition(merged[1].percent == 88, "the fresher HID level wins over the profiler's")

        precondition(AccessoryReadings.symbol(name: "Pixel Buds", majorClass: 4, minorClass: 1) == "headphones",
                     "headphones by name")
        precondition(AccessoryReadings.symbol(name: "BT-123", majorClass: 5, minorClass: 0x25) ==
                     "rectangle.and.hand.point.up.left", "a digitizer pointer is a trackpad")
        precondition(AccessoryReadings.symbol(name: "Car", majorClass: 4, minorClass: 8) == "car", "a car kit")
    }

    static func lowWatch() {
        var watch = AccessoryLowWatch()
        let steps: [(Int, Bool)] = [
            (15, false), (14, false), (24, false), (20, false), (25, false), (20, true), (19, false), (22, false),
            (24, false), (18, false), (30, false), (21, false), (20, true),
        ]
        for (percent, warns) in steps {
            let warned = !watch.consume([device("Mouse", percent)]).isEmpty
            precondition(warned == warns, "at \(percent)%: warns \(warns)")
        }
        precondition(watch.consume([device("Keyboard", 10, .keyboard)]).isEmpty, "a new accessory's level is a baseline")
        precondition(watch.consume([]).isEmpty, "a missing reading ends nothing")
        precondition(watch.consume([device("Mouse", 19)]).isEmpty, "so the episode that warned stays spent")
        watch.forget("mouse ")
        precondition(watch.consume([device("Mouse", 30)]).isEmpty, "after a disconnect the first reading is silent")
        precondition(!watch.consume([device("Mouse", 20)]).isEmpty, "then it warns again")
    }

    static func connections() {
        var state = AccessoryConnections()
        state.baseline(["a"])
        precondition(!state.connect("a"), "connected at start: silent")
        precondition(state.connect("b") && !state.connect("b"), "a new connection once")
        state.disconnect("b")
        precondition(state.connect("b"), "a reconnection is news again")
        precondition(!state.connect(""), "no address, no notice")
    }

    static func policy() {
        precondition(!AccessoryPolicy.announcesConnection(name: "MacBook", majorClass: 1), "computers never")
        precondition(!AccessoryPolicy.announcesConnection(name: "iPhone", majorClass: 2), "phones never")
        precondition(!AccessoryPolicy.announcesConnection(name: "Router", majorClass: 3), "access points never")
        precondition(AccessoryPolicy.announcesConnection(name: "Headset", majorClass: 4), "audio yes")
        precondition(AccessoryPolicy.announcesConnection(name: "Thing", majorClass: 0), "an unclassed device yes")
        precondition(AccessoryPolicy.announcesAppleConnects, "Apple accessories announced until the desk test says not")
        precondition(AccessoryPolicy.isApple("Kim's AirPods Pro") && !AccessoryPolicy.isApple("MX Master 3"),
                     "Apple accessories by name")

        let now = Date(timeIntervalSinceReferenceDate: 100)
        let names = ["kim's airpods pro": now.addingTimeInterval(5), "magic mouse": now.addingTimeInterval(-1)]
        precondition(AccessoryPolicy.hides(banner: ["Kim's AirPods Pro", "Connected"], names: names, now: now),
                     "macOS's banner for the accessory we just announced")
        precondition(!AccessoryPolicy.hides(banner: ["Magic Mouse", "Connected"], names: names, now: now),
                     "not once its window has passed")
        precondition(!AccessoryPolicy.hides(banner: ["Messages", "See you at 5"], names: names, now: now),
                     "never another app's banner")
        precondition(!AccessoryPolicy.hides(banner: ["x"], names: ["": .distantFuture], now: now), "an empty name hides nothing")
    }

    static func page() {
        precondition(AccessoryPage.page([]) == nil, "no levels, no tab")
        let pods = device("AirPods", 40, .audio, parts: [.init(name: .left, percent: 80), .init(name: .batteryCase, percent: 40)])
        let page = AccessoryPage.page([device("Magic Mouse", 15), pods])!
        precondition(page.id == "accessories" && page.order == 25, "its tab between System and Day")
        precondition(page.line.text == "Magic Mouse: 15%" && page.line.detail == "2 accessories", "Home names the lowest")
        guard case let .cards(group) = page.blocks.first else { preconditionFailure("one card row") }
        precondition(group.cards.map(\.title) == ["Magic Mouse", "AirPods"], "a card each, lowest first")
        guard case let .meters(mouse) = group.cards[0].body, case let .meters(parts) = group.cards[1].body else {
            preconditionFailure("meters")
        }
        precondition(mouse.map(\.label) == ["Battery"] && mouse[0].warning && mouse[0].value == "15%", "low is warned")
        precondition(parts.map(\.label) == ["Left", "Case"] && !parts[0].warning, "AirPods show their parts")
        precondition(group.cards[1].spoken == "AirPods, Left 80%, Case 40%", "one VoiceOver sentence")
    }

    static func module() async {
        let rig = Rig(suite: "nc-accessories-module", on: false)
        let module = rig.module()
        rig.context.attach(module)
        module.start()
        precondition(system.live == 1 && rig.presenter.watcher != nil, "watches connections and the page")

        system.hid = [device("Magic Mouse", 50)]
        await module.read(profilerAge: AccessoriesModule.profilerAge)
        precondition(rig.texts.isEmpty, "the first reading is silent")
        precondition(rig.presenter.page?.line.text == "Magic Mouse: 50%", "the page lists the mouse")
        precondition(system.profilerReads == 1, "the profiler runs on the first read")
        await module.read(profilerAge: AccessoriesModule.profilerAge)
        precondition(system.profilerReads == 1, "and not again inside its age")

        system.connection?(.connected(name: "Kim's AirPods Pro", majorClass: 4, minorClass: 6))
        await settle()
        precondition(rig.texts == ["Kim's AirPods Pro: Connected"], "a connection is announced")
        precondition(rig.presenter.posts[0].symbol == "airpodspro" && !rig.presenter.posts[0].isFailure, "its glyph")
        precondition(system.bannerNames["kim's airpods pro"] == system.now.addingTimeInterval(10),
                     "macOS's banner for it may be hidden for 10 s")
        system.profiler = [device("Kim's AirPods Pro", 60, .audio)]
        await settle()
        await module.read(profilerAge: 0)
        precondition(system.profilerReads >= 2, "levels are read again after a connection")
        precondition(module.devices.map(\.name) == ["Magic Mouse", "Kim's AirPods Pro"], "both listed")

        rig.presenter.taps["accessories.connected.kim's airpods pro"]?()
        precondition(rig.presenter.shown == ["accessories"], "a tap opens the Accessories page")

        system.connection?(.connected(name: "iPhone", majorClass: 2, minorClass: 3))
        await settle()
        precondition(rig.texts.count == 1, "a phone is never announced")

        system.hid = [device("Magic Mouse", 18)]
        await module.read(profilerAge: 300)
        await settle()
        precondition(rig.texts.last == "Magic Mouse: Low battery: 18%", "a fall to 20% or below warns")
        precondition(rig.presenter.posts.last?.isFailure == true, "in the failure ink")
        precondition(system.bannerNames["magic mouse"] == .distantFuture, "macOS's later warning counts as a duplicate")
        await module.read(profilerAge: 300)
        precondition(rig.texts.count == 2, "once per discharge")

        rig.defaults.set(false, forKey: AccessoryPolicy.connectKey)
        system.connection?(.connected(name: "MX Master 3", majorClass: 5, minorClass: 0x20))
        await settle()
        precondition(rig.texts.count == 2, "the Connected checkbox off silences connections")

        system.connection?(.disconnected(name: "Kim's AirPods Pro"))
        await settle()
        precondition(rig.presenter.ends == ["accessories.connected.kim's airpods pro"], "its notice goes")
        precondition(!module.devices.contains { $0.name == "Kim's AirPods Pro" }, "and it leaves the page")

        module.stop()
        await settle()
        precondition(rig.presenter.page == nil && rig.presenter.watcher == nil, "stop clears the page")
        precondition(rig.presenter.ends.contains("accessories.low.magic mouse"), "and ends its notices")
        precondition(system.live == 0, "and lets go of Bluetooth")
        system.connection?(.connected(name: "Late", majorClass: 4, minorClass: 1))
        await settle()
        precondition(rig.texts.count == 2, "a stopped module posts nothing")
        rig.context.attach(nil)
    }

    static func switches() async {
        system.hid = []
        let rig = Rig(suite: "nc-accessories-switch", on: true)
        await settle()
        precondition(rig.context.module(AccessoriesModule.self)?.isRunning == true, "the switch starts the module")
        rig.controller.preferences.set("accessoryNotices", on: false)
        await settle()
        precondition(rig.context.module(AccessoriesModule.self) == nil, "and off stops it")
    }
}
