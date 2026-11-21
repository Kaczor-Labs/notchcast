// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemNotices/SystemNoticesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemNotices/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemNotices/Service/SystemNoticesModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import SwiftUI

// The shipped watchers and settings view are left out: these stand in, so `makeModule` runs as shipped.

struct SystemNoticesSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

final class SystemNoticesWatcher {
    private let cancel: () -> Void
    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }
    deinit { cancel() }
}

/// The system as the watchers would report it: each handler the module handed over, and a clock.
@MainActor
final class FakeSystem {
    var wifi: SystemNoticesModule.LinkChanged?
    var vpn: SystemNoticesModule.LinkChanged?
    var battery: (@MainActor @Sendable (Int, Bool) -> Void)?
    var sleep: (@MainActor @Sendable () -> Void)?
    var wake: (@MainActor @Sendable () -> Void)?
    var hasBattery = true
    var live = 0
    var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }

    func watcher() -> SystemNoticesWatcher {
        live += 1
        return SystemNoticesWatcher { MainActor.assumeIsolated { system.live -= 1 } }
    }
}

@MainActor let system = FakeSystem()

extension SystemNoticesModule {
    typealias LinkChanged = @MainActor @Sendable (Bool) -> Void

    static func watchWiFi(_ changed: @escaping LinkChanged) -> SystemNoticesWatcher? {
        system.wifi = changed
        return system.watcher()
    }

    static func watchVPN(_ changed: @escaping LinkChanged) -> SystemNoticesWatcher? {
        system.vpn = changed
        return system.watcher()
    }

    static func watchBattery(_ changed: @escaping @MainActor @Sendable (Int, Bool) -> Void) -> SystemNoticesWatcher? {
        guard system.hasBattery else { return nil }
        system.battery = changed
        return system.watcher()
    }

    static func watchSleep(sleep: @escaping @MainActor @Sendable () -> Void,
                           wake: @escaping @MainActor @Sendable () -> Void) -> SystemNoticesWatcher? {
        system.sleep = sleep
        system.wake = wake
        return system.watcher()
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

    init(suite: String, on: Bool?) {
        defaults = UserDefaults(suiteName: suite)!
        if let on { defaults.set(on, forKey: "systemNotices") }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [SystemNoticesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { system.now })
        controller.start()
    }

    var module: SystemNoticesModule? {
        controller.context(forSwitch: "systemNotices")?.module(SystemNoticesModule.self)
    }

    /// What the module's own timer does once the clock reaches the deadline.
    func pass(_ seconds: TimeInterval) {
        system.advance(seconds)
        module?.evaluate()
    }

    var texts: [String] { presenter.posts.map(\.text) }
}

/// The checkbox hook hops to the main actor; a few turns let it run, with no clock involved.
@MainActor
func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

@main
@MainActor
enum SystemNoticesModuleTests {
    static func main() async {
        descriptor()
        linkWatch()
        batteryWatch()
        await wifiAndVPN()
        await battery()
        print("PASS nc-SystemNotices-module-test")
    }

    static func descriptor() {
        let only = SystemNoticesAddon.switches
        precondition(only.map(\.id) == ["systemNotices"], "v1 switch id")
        precondition(only[0].defaultEnabled == false, "off by default")
        precondition(only[0].category == .notices, "Notices category")
        precondition(NotchcastPane.holding(.notices) == .islandContent, "in Island Content")
        precondition(SystemNoticesAddon.settings.map(\.switchID) == ["systemNotices"], "the checkboxes sit under it")
        precondition(LinkWatch.settle == 5 && LinkWatch.wakeQuiet == 30, "5 s debounce, 30 s quiet after wake")
        precondition(BatteryWatch.threshold == 20 && BatteryWatch.recovery == 25, "Vorssaint's 20%, re-armed at 25%")
    }

    static func linkWatch() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

        var watch = LinkWatch()
        precondition(watch.due(at: start) == nil, "nothing read yet: nothing to say")
        watch.observe(false, at: start)
        precondition(watch.announced == false && watch.deadline == nil, "the first reading is a silent baseline")
        precondition(watch.due(at: at(60)) == nil, "so a link down at launch is never announced")

        watch.observe(true, at: at(10))
        precondition(watch.deadline == at(15), "a change waits out the settle time")
        precondition(watch.due(at: at(14.9)) == nil, "not before it")
        precondition(watch.due(at: at(15)) == true, "then it is announced")
        precondition(watch.due(at: at(16)) == nil, "once")

        watch.observe(false, at: at(20))
        watch.observe(true, at: at(21))
        precondition(watch.deadline == nil, "a 1-second blip that came back leaves nothing pending")
        precondition(watch.due(at: at(30)) == nil, "and is never announced")

        watch.observe(false, at: at(40))
        watch.observe(false, at: at(42))
        precondition(watch.deadline == at(45), "a repeated reading does not restart the settle time")
        watch.observe(true, at: at(43))
        watch.observe(false, at: at(44))
        precondition(watch.deadline == at(49), "a flap restarts it from the last change")
        precondition(watch.due(at: at(49)) == false, "the drop that held is announced")

        watch.observe(true, at: at(50))
        watch.quiet(until: .distantFuture)
        precondition(watch.announced == true && watch.deadline == nil, "going to sleep takes the link as up")
        watch.observe(false, at: at(60))
        precondition(watch.deadline == nil, "nothing is due while asleep")
        watch.quiet(until: at(130))
        precondition(watch.deadline == at(135), "a drop over sleep must hold past the quiet")
        watch.observe(true, at: at(100))
        watch.observe(false, at: at(110))
        watch.observe(true, at: at(132))
        precondition(watch.deadline == nil, "a drop inside the quiet that returns after it leaves nothing")
        precondition(watch.due(at: at(200)) == nil, "so no lone Connected")
        watch.observe(false, at: at(200))
        precondition(watch.due(at: at(205)) == false, "after the quiet, changes are news again")

        var login = LinkWatch()
        login.quiet(until: at(30))
        login.observe(false, at: start)
        login.observe(true, at: at(8))
        precondition(login.announced == true && login.due(at: at(60)) == nil, "a link up within the quiet is silent")
        login.observe(false, at: at(20))
        precondition(login.deadline == at(35), "a drop that holds past the quiet")
        precondition(login.due(at: at(34)) == nil && login.due(at: at(35)) == false, "is told at its end plus settle")
    }

    static func batteryWatch() {
        var watch = BatteryWatch()
        let readings: [(percent: Int, onAC: Bool, warns: Int?)] = [
            (15, false, nil), (14, false, nil), (21, false, nil), (20, false, nil), (25, false, nil), (20, false, 20),
            (21, false, nil), (20, false, nil), (24, false, nil), (19, false, nil), (25, true, nil), (18, true, nil),
            (17, false, 17), (24, false, nil), (19, true, nil), (30, true, nil), (22, false, nil), (21, false, nil),
            (20, false, 20),
        ]
        for (index, reading) in readings.enumerated() {
            precondition(watch.observe(percent: reading.percent, onAC: reading.onAC) == reading.warns,
                         "reading \(index): \(reading.percent)% onAC \(reading.onAC)")
        }

        var launchedLow = BatteryWatch()
        precondition(launchedLow.observe(percent: 10, onAC: false) == nil, "launch below 20%: silent baseline")
        precondition(launchedLow.observe(percent: 9, onAC: false) == nil, "and no warning on the way down")
        var launched21 = BatteryWatch()
        precondition(launched21.observe(percent: 21, onAC: false) == nil, "launch just above 20%")
        precondition(launched21.observe(percent: 20, onAC: false) == 20, "is armed")
        var onCharger = BatteryWatch()
        precondition(onCharger.observe(percent: 50, onAC: true) == nil, "launch on AC")
        precondition(onCharger.observe(percent: 20, onAC: true) == nil, "nothing while on AC")
        precondition(onCharger.observe(percent: 19, onAC: false) == 19, "unplugged while low: the warning still due")
    }

    static func wifiAndVPN() async {
        let suite = "nc-SystemNotices-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        var rig = Rig(suite: suite, on: nil)
        precondition(rig.module == nil && system.wifi == nil, "default off: no module, no watchers")
        rig.controller.stop()

        rig = Rig(suite: suite, on: true)
        precondition(rig.module?.isRunning == true && system.live == 4, "on: four watchers")
        system.wifi?(true)
        system.vpn?(false)
        rig.pass(60)
        precondition(rig.presenter.posts.isEmpty, "the state at launch is never announced")

        system.wifi?(false)
        rig.pass(1)
        system.wifi?(true)
        rig.pass(10)
        precondition(rig.presenter.posts.isEmpty, "a 1-second blip gives none")

        system.wifi?(false)
        rig.pass(5)
        system.wifi?(true)
        rig.pass(5)
        precondition(rig.texts == ["Wi-Fi disconnected", "Wi-Fi connected"], "off and on gives two: \(rig.texts)")
        let drop = rig.presenter.posts[0]
        precondition(drop.id == "systemNotices.wifi" && drop.symbol == "wifi.slash" && drop.isFailure, "drop look")
        let back = rig.presenter.posts[1]
        precondition(back.id == drop.id && back.symbol == "wifi" && !back.isFailure, "return look, same id")

        system.vpn?(true)
        rig.pass(5)
        system.vpn?(false)
        rig.pass(5)
        precondition(Array(rig.texts.suffix(2)) == ["VPN connected", "VPN disconnected"], "VPN up and down")
        precondition(rig.presenter.posts.last?.symbol == "exclamationmark.shield", "VPN down glyph")

        let count = rig.presenter.posts.count
        system.sleep?()
        system.wifi?(false)
        system.vpn?(true)
        system.advance(3600)
        system.wake?()
        system.wifi?(true)
        rig.pass(10)
        system.wifi?(false)
        rig.pass(22)
        system.wifi?(true)
        rig.pass(40)
        precondition(rig.presenter.posts.count == count, "sleep, and a drop inside the quiet back after it: \(rig.texts)")
        system.wifi?(false)
        rig.pass(5)
        precondition(rig.texts.last == "Wi-Fi disconnected" && rig.presenter.posts.count == count + 1, "then news again")

        let unticked = system.wifi
        rig.defaults.set(false, forKey: SystemNoticesPolicy.wifiKey)
        await settle()
        precondition(system.live == 3, "its checkbox off stops the Wi-Fi watcher: \(system.live)")
        precondition(rig.presenter.ends.contains("systemNotices.wifi"), "and ends its notice")
        unticked?(true)
        rig.pass(5)
        precondition(rig.presenter.posts.count == count + 1, "a reading it had queued says nothing")
        system.vpn?(false)
        rig.pass(5)
        precondition(rig.texts.last == "VPN disconnected", "but not the VPN")
        rig.defaults.set(true, forKey: SystemNoticesPolicy.wifiKey)
        await settle()
        precondition(system.live == 4 && system.wifi != nil, "ticked again: a new watcher")
        system.wifi?(true)
        rig.pass(10)
        precondition(rig.presenter.posts.count == count + 2, "whose first reading is a silent baseline")

        let stale = system.wifi
        rig.controller.stop()
        precondition(rig.module == nil, "switching off drops the module")
        precondition(Set(rig.presenter.ends) == ["systemNotices.wifi", "systemNotices.vpn", "systemNotices.battery"],
                     "and ends its notices: \(rig.presenter.ends)")
        rig = Rig(suite: suite, on: true)
        system.wifi?(false)
        system.vpn?(true)
        rig.pass(8)
        system.wifi?(true)
        system.vpn?(false)
        system.vpn?(true)
        stale?(false)
        rig.pass(60)
        precondition(rig.presenter.posts.isEmpty, "login is silent, and a stopped run's reading never reaches the next")
        rig.controller.stop()
    }

    static func battery() async {
        let suite = "nc-SystemNotices-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        var rig = Rig(suite: suite, on: true)
        system.battery?(40, false)
        system.battery?(21, false)
        system.battery?(20, false)
        system.battery?(15, false)
        precondition(rig.texts == ["Low battery: 20%"], "once at 20%: \(rig.texts)")
        let notice = rig.presenter.posts[0]
        precondition(notice.id == "systemNotices.battery" && notice.symbol == "battery.25percent" && notice.isFailure,
                     "its id and glyph")
        system.battery?(80, true)
        let unticked = system.battery
        rig.defaults.set(false, forKey: SystemNoticesPolicy.batteryKey)
        await settle()
        precondition(system.live == 3, "its checkbox off stops the battery watcher")
        unticked?(20, false)
        precondition(rig.presenter.posts.count == 1, "and spends no warning")
        rig.defaults.set(true, forKey: SystemNoticesPolicy.batteryKey)
        await settle()
        system.battery?(15, false)
        precondition(rig.texts.last == "Low battery: 15%", "ticked again below 20%, still armed: \(rig.texts)")
        rig.controller.stop()

        system.hasBattery = false
        defer { system.hasBattery = true }
        system.battery = nil
        rig = Rig(suite: suite, on: true)
        precondition(system.battery == nil && rig.module?.isRunning == true, "a Mac without a battery watches none")
        rig.controller.stop()
    }
}
