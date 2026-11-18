// notchcast-sources: Tinycast/Features/Notchcast/System/SystemAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/System/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/System/Service/SystemModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit

// The shipped probe reads the real Mac; this stands in, so `makeModule` compiles as shipped and reads nothing.
enum SystemProbe {
    static func sample() async -> SystemCounters? { nil }
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-System-module-test: \(message)") }
}

/// Stands in for the Mac and the clock: reads come from a script, and a sleep takes no time.
@MainActor
final class FakeMac {
    var script: [SystemCounters] = []
    var sleeps: [Duration] = []
    var reads = 0
    var holds = false
    var gate: CheckedContinuation<Void, Never>?

    func read() async -> SystemCounters? {
        reads += 1
        if holds { await withCheckedContinuation { gate = $0 } }
        return script.isEmpty ? nil : script.removeFirst()
    }

    /// The loop ends with the script, so a run is as long as its reads and never waits.
    func sleep(_ duration: Duration) throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        if script.isEmpty { throw CancellationError() }
    }

    static func counters(at: TimeInterval, busy: UInt64, total: UInt64) -> SystemCounters {
        SystemCounters(at: at, cpuBusyTicks: busy, cpuTotalTicks: total, processorCount: 8,
                       memoryUsed: 8_000_000_000, memoryTotal: 16_000_000_000, memoryPressure: .normal,
                       diskFree: 200_000_000_000, diskTotal: 500_000_000_000, network: nil, processes: [],
                       thermal: .nominal)
    }
}

@MainActor
final class PageRecorder: IslandPresenting {
    var pages: [IslandPage?] = []
    var statuses: [IslandStatus?] = []
    var action: (@MainActor (String) -> Void)?

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(id == SystemPage.statusID, "the add-on owns one status")
        statuses.append(status)
    }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == SystemPage.id, "the add-on posts only the System page")
        pages.append(page)
        action = onAction
    }
}

/// The module as its hook starts it, on a scripted Mac: cadence, the page, the hot status and teardown.
@MainActor
@main
struct SystemModuleTests {
    static func main() async {
        switchShape()
        await lifecycle()
        await hotStatus()
        await refresh()
        await staleRead()
        print("PASSED")
    }

    static func make(_ mac: FakeMac, _ presenter: PageRecorder) -> (SystemModule, NotchcastContext) {
        let suite = "nc-system-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: SystemAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date(timeIntervalSince1970: 0) }, onTapsChanged: {})
        let module = SystemModule(context: context, probe: { await mac.read() }, sleep: { try await mac.sleep($0) },
                                  locale: Locale(identifier: "en_US"))
        return (module, context)
    }

    static func switchShape() {
        check(SystemAddon.switches.map(\.id) == ["systemPage"], "the switch id is frozen")
        let entry = SystemAddon.switches[0]
        check(!entry.defaultEnabled && entry.requiredGrants.isEmpty && entry.dependencies.isEmpty,
              "off by default, and it needs no grant")
        let (_, context) = make(FakeMac(), PageRecorder())
        check(SystemAddon.makeModule(context) is SystemModule, "the switch has a module as its user path")
    }

    static func lifecycle() async {
        let mac = FakeMac()
        let presenter = PageRecorder()
        let (module, _) = make(mac, presenter)
        module.stop()
        check(presenter.pages.isEmpty && presenter.statuses.isEmpty, "stopping a module that never ran posts nothing")

        mac.script = [FakeMac.counters(at: 100, busy: 0, total: 0), FakeMac.counters(at: 101, busy: 180, total: 1000)]
        module.start()
        module.start()
        await module.loop?.value
        check(mac.reads == 2 && mac.sleeps == [SystemModule.warmUp, SystemModule.interval],
              "one loop: a read, the warm-up, a read, then the background interval: \(mac.sleeps)")
        check(presenter.pages.count == 1 && presenter.pages[0]?.id == SystemPage.id,
              "the page appears with the first rate, not with the first read")
        check(presenter.statuses.isEmpty, "a calm Mac sets no status")

        module.stop()
        check(presenter.pages.count == 2 && presenter.pages[1] == nil && presenter.statuses == [nil],
              "switching off removes the page and the status")
        mac.script = [FakeMac.counters(at: 300, busy: 0, total: 0), FakeMac.counters(at: 301, busy: 500, total: 1000)]
        module.start()
        await module.loop?.value
        check(presenter.pages.count == 3 && presenter.pages[2] != nil, "switching on again starts from a new baseline")
        module.stop()
    }

    static func hotStatus() async {
        let mac = FakeMac()
        let presenter = PageRecorder()
        let (module, _) = make(mac, presenter)
        mac.script = [
            FakeMac.counters(at: 100, busy: 0, total: 0), FakeMac.counters(at: 101, busy: 950, total: 1000),
            FakeMac.counters(at: 116, busy: 1900, total: 2000), FakeMac.counters(at: 131, busy: 2850, total: 3000),
            FakeMac.counters(at: 146, busy: 2950, total: 4000),
        ]
        module.start()
        await module.loop?.value
        check(presenter.pages.count == 4, "every rate posts the page again")
        check(presenter.pages[0]?.line.symbol == "cpu" && presenter.pages[1]?.line.symbol == SystemPage.warningSymbol,
              "the warning waits for load that holds across reads")
        check(presenter.statuses == [SystemPage.status([.cpu]), nil],
              "the status is set once while hot, not on every read, and cleared when it passes")
        check(presenter.pages[3]?.line.symbol == "cpu", "the page calms down with it")
        module.stop()
    }

    static func refresh() async {
        let mac = FakeMac()
        let presenter = PageRecorder()
        let (module, _) = make(mac, presenter)
        mac.script = [FakeMac.counters(at: 100, busy: 0, total: 0), FakeMac.counters(at: 101, busy: 100, total: 1000)]
        module.start()
        await module.loop?.value

        mac.script = [FakeMac.counters(at: 101.2, busy: 150, total: 1200)]
        presenter.action?(IslandPage.refreshAction)
        await module.refresh?.value
        check(mac.reads == 3 && presenter.pages.count == 1, "Command-R right after a read keeps the page it has")
        mac.script = [FakeMac.counters(at: 106, busy: 2600, total: 6000)]
        presenter.action?(IslandPage.refreshAction)
        await module.refresh?.value
        check(mac.reads == 4 && presenter.pages.count == 2, "Command-R reads at once")
        guard case .meter(let cpu)? = presenter.pages[1]?.blocks.first else { fatalError("nc-System-module-test: CPU tile") }
        check(cpu.fraction == 0.5, "its rate runs from the last kept read: \(cpu.fraction)")
        presenter.action?("other")
        check(mac.reads == 4, "only the refresh action reads")
        module.stop()
    }

    static func staleRead() async {
        let mac = FakeMac()
        let presenter = PageRecorder()
        let (module, _) = make(mac, presenter)
        mac.script = [FakeMac.counters(at: 100, busy: 0, total: 0), FakeMac.counters(at: 101, busy: 100, total: 1000)]
        mac.holds = true
        module.start()
        while mac.gate == nil { await Task.yield() }
        let loop = module.loop
        module.stop()
        mac.holds = false
        mac.gate?.resume()
        await loop?.value
        check(presenter.pages == [nil] && presenter.statuses == [nil] && mac.sleeps.isEmpty,
              "a read that returns after the switch went off posts nothing and ends the loop")
    }
}
