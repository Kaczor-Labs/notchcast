// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/SystemMonitorAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Service/SystemMonitorModule.swift Tinycast/Features/Notchcast/SystemMonitor/Service/MonitorSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
// notchcast-sources: Tests/nc-SystemMonitor-fixtures.swift
import SwiftUI

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-SystemMonitor-module-test: \(message)") }
}

/// Stands in for the live reads, so the descriptor compiles as shipped without touching the Mac.
extension MonitorSystem {
    static func live() -> MonitorSystem {
        MonitorSystem(read: { _ in preconditionFailure("the harness never reads the Mac") },
                      sleep: { _ in preconditionFailure("the harness never sleeps") }, processorCount: 1)
    }
}

/// A scripted Mac: each read hands out the next CPU load; each sleep runs the next step, which may end the loop.
@MainActor
final class FakeMac {
    var time: TimeInterval = 0
    var cpu = 0.2
    var pressure = MonitorPressure.normal
    var reads: [Bool] = []
    var sleeps: [Duration] = []
    var steps: [@MainActor () -> Void] = []
    private var busy: UInt64 = 0
    private var total: UInt64 = 0

    func read(_ detail: Bool) -> MonitorReading {
        reads.append(detail)
        busy += UInt64(cpu * 1000)
        total += 1000
        let step = Double(reads.count)
        return MonitorFixtures.reading(at: time, busy: busy, total: total + 1000, received: UInt64(step) * 1000,
                                       sent: UInt64(step) * 100, detail: detail, pressure: pressure, step: step)
    }

    func sleep(_ duration: Duration) throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        time += duration == MonitorBoard.shownInterval ? 2 : 15
        if steps.isEmpty { throw CancellationError() }
        steps.removeFirst()()
    }

    var system: MonitorSystem {
        MonitorSystem(read: { await self.read($0) }, sleep: { try await self.sleep($0) }, processorCount: 4)
    }
}

@MainActor
final class Recorder: IslandPresenting {
    var pages: [IslandPage?] = []
    var statuses: [IslandStatus?] = []
    var action: (@MainActor (String) -> Void)?
    var tap: (@MainActor () -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?
    var shown: [String] = []

    func showLevel(_ level: IslandLevel) { check(false, "the System add-on shows no level") }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { check(false, "it posts no notice") }
    func end(notice id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(id == MonitorPage.id, "one status, under the page's id")
        statuses.append(status)
        tap = onTap
    }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == MonitorPage.id, "the add-on posts only the System page")
        pages.append(page)
        action = onAction
    }

    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?) {
        check(id == MonitorPage.id, "the add-on watches only the System page")
        watcher = onChange
    }

    func showPage(id: String) { shown.append(id) }
}

/// The module as its hook starts it, on a scripted Mac: cadence, visibility, the hot glyph, Command-R, teardown.
@MainActor
@main
struct SystemMonitorModuleTests {
    static func main() async {
        switchShape()
        await hidden()
        await shown()
        await hot()
        await refresh()
        await switchOff()
        print("PASSED")
    }

    /// A step that shows or hides the page starts a new loop; wait for the last one.
    static func settle(_ module: SystemMonitorModule) async {
        while let loop = module.loop {
            await loop.value
            if module.loop == loop { return }
        }
    }

    static func make(_ mac: FakeMac, _ presenter: Recorder) -> (SystemMonitorModule, NotchcastContext) {
        let suite = "nc-system-monitor-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let context = NotchcastContext(
            defaults: defaults,
            preferences: NotchcastPreferences(defaults: defaults, switches: SystemMonitorAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date(timeIntervalSince1970: 0) }, onTapsChanged: {})
        return (SystemMonitorModule(context: context, system: mac.system, locale: MonitorFixtures.locale), context)
    }

    static func switchShape() {
        check(SystemMonitorAddon.switches.map(\.id) == ["systemPage"], "the switch id is frozen")
        let entry = SystemMonitorAddon.switches[0]
        check(!entry.defaultEnabled && entry.requiredGrants.isEmpty && entry.dependencies.isEmpty,
              "off by default, and it needs no grant: no root, no Accessibility")
        let (_, context) = make(FakeMac(), Recorder())
        check(SystemMonitorAddon.makeModule(context) is SystemMonitorModule, "the switch has a module as its user path")
    }

    /// Closed, only the hot check reads: every 15 s, never the network or the process walk, and no page post.
    static func hidden() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.steps = [{}, {}]
        module.start()
        module.start()
        await module.loop?.value
        check(mac.reads == [false, false, false], "three plain reads: \(mac.reads)")
        check(mac.sleeps == [MonitorBoard.hiddenInterval, MonitorBoard.hiddenInterval, MonitorBoard.hiddenInterval],
              "15 s apart while hidden")
        check(presenter.pages.count == 1 && presenter.pages[0]?.line.text == "Measuring…",
              "one page at start, so Home lists it; hidden reads post nothing more")
        check(presenter.statuses.isEmpty, "nothing hot, no status")
        module.stop()
    }

    /// On show it reads at once with the page's detail, then every 2 s; hidden again it drops to the hot check.
    static func shown() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.steps = [{
            presenter.watcher?(true)
            mac.steps = [{}, {}, { presenter.watcher?(false) }]
        }]
        module.start()
        await settle(module)
        check(mac.reads == [false, true, true, true, false], "\(mac.reads)")
        check(Array(mac.sleeps.suffix(4)) == [.seconds(2), .seconds(2), .seconds(2), .seconds(15)],
              "2 s while shown, 15 s once hidden: \(mac.sleeps)")
        guard let page = presenter.pages.last ?? nil, case .cards(let tiles) = page.blocks.first else {
            return check(false, "the page shows tiles")
        }
        check(tiles.cards.allSatisfy { !$0.dimmed }, "every tile filled once two detail reads came in")
        check(page.blocks.count == 4, "the header and two processes under the tiles: \(page.blocks.count)")
        check(page.line.text == "Disk 80% full", "Home names the busiest resource: \(page.line.text)")
        let posts = presenter.pages.count
        presenter.watcher?(false)
        check(presenter.pages.count == posts, "hiding twice changes nothing")
        module.stop()
    }

    static func hot() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.cpu = 0.95
        mac.steps = [{}, {}, { mac.cpu = 0.5 }, {}]
        module.start()
        await module.loop?.value
        check(presenter.statuses.count == 2, "hot once, cool once: \(presenter.statuses)")
        check(presenter.statuses[0]?.symbol == "cpu" && presenter.statuses[0]?.text == "Hot",
              "held over the limit on hidden reads, the closed island shows CPU Hot")
        check(presenter.statuses[1] == nil, "under 75 % the glyph goes")
        presenter.tap?()
        check(presenter.shown == [MonitorPage.id], "its tap opens the System page")
        mac.pressure = .critical
        mac.steps = [{}]
        presenter.watcher?(true)
        await module.loop?.value
        check(presenter.statuses.last??.symbol == "memorychip", "critical pressure shows at once")
        module.stop()
        check(presenter.statuses.last! == nil, "switching off clears the glyph")
    }

    static func refresh() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.steps = [{ presenter.watcher?(true) }]
        module.start()
        await settle(module)
        let reads = mac.reads.count
        mac.steps = []
        presenter.action?(IslandPage.refreshAction)
        await module.loop?.value
        check(mac.reads.count == reads + 1, "Command-R reads at once")
        module.stop()
    }

    static func switchOff() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        module.start()
        let watcher = presenter.watcher
        let loop = module.loop
        mac.steps = [{ module.stop() }]
        await loop?.value
        check(presenter.pages.last! == nil, "switching off removes the page")
        let reads = mac.reads.count
        watcher?(true)
        check(module.loop == nil && mac.reads.count == reads, "after stop nothing samples, shown or not")
        module.stop()
        check(presenter.pages.count == 2, "a second stop posts nothing")
    }
}
