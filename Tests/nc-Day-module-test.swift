// notchcast-sources: Tinycast/Features/Notchcast/Day/DayAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Day/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Day/Service/*.swift
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
// notchcast-sources: Tests/nc-Day-fixtures.swift
import SwiftUI

// The shipped row is a Settings view; this stands in, so the descriptor compiles as shipped.
struct DaySettingsView: View {
    let context: NotchcastContext
    var body: some View { EmptyView() }
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Day-module-test: \(message)") }
}

/// Stands in for the network, the clock and stock Calendar: answers by host, and a sleep that takes no time.
@MainActor
final class FakeWorld {
    var now = DayFixtures.now
    var online = true
    var cityKnown = true
    var requests: [String] = []
    var seen: [[String]] = []
    var steps: [@MainActor () -> Void] = []
    var events: [NotchcastEvent] = []
    var scheduleOpens = 0
    var holds = false
    var gates: [CheckedContinuation<Void, Never>] = []

    func get(_ url: URL) async -> Data? {
        let host = url.host() ?? ""
        let kind = host.hasPrefix("geocoding") ? "city" : host.hasPrefix("api.open-meteo") ? "weather" : "quote"
        requests.append(kind == "quote" ? url.lastPathComponent : kind)
        if holds { await withCheckedContinuation { gates.append($0) } }
        guard online, url.scheme == "https" else { return nil }
        switch kind {
        case "city": return cityKnown ? DayFixtures.search : DayFixtures.noCity
        case "weather": return DayFixtures.forecast
        default:
            let symbol = url.lastPathComponent
            return symbol == "NOPE" ? DayFixtures.unknownSymbol : DayFixtures.chart(symbol, price: 352.79, change: 0.25)
        }
    }

    /// Each sleep runs the next step, which moves the clock; the loop ends with the script.
    func sleep(_ duration: Duration) throws {
        try Task.checkCancellation()
        check(duration == DayModule.tick, "the loop wakes once a minute")
        if steps.isEmpty { throw CancellationError() }
        steps.removeFirst()()
    }

    func release() {
        holds = false
        gates.forEach { $0.resume() }
        gates = []
    }

    func take() -> [String] {
        defer { requests = [] }
        return requests.sorted()
    }

    /// Files what was asked since the last step, then moves the clock on.
    func note(advance seconds: TimeInterval = 0) {
        seen.append(take())
        now += seconds
    }
}

@MainActor
final class PageRecorder: IslandPresenting {
    var pages: [IslandPage?] = []
    var action: (@MainActor (String) -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?

    func showLevel(_ level: IslandLevel) { check(false, "the Day add-on shows no level") }
    func end(notice id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        check(false, "weather and markets never post a notice to the closed island")
    }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(false, "weather and markets never enter the closed island")
    }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == DayPage.id, "the add-on posts only the Day page")
        pages.append(page)
        action = onAction
    }

    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?) {
        check(id == DayPage.id, "the add-on watches only the Day page")
        watcher = onChange
    }

    func titles(_ index: Int) -> [String] {
        (pages[index]?.blocks ?? []).compactMap { if case .row(let row) = $0 { row.title } else { nil } }
    }

    func trailing(_ index: Int, _ title: String) -> String? {
        for case .row(let row) in pages[index]?.blocks ?? [] where row.title == title { return row.trailing }
        return nil
    }
}

/// The module as its hook starts it, on a fake network with an injected clock: cadence, visibility, keys, teardown.
@MainActor
@main
struct DayModuleTests {
    static func main() async {
        switchShape()
        await nothingChosen()
        await cadence()
        await visibility()
        await offline()
        await keys()
        await city()
        await staleLoad()
        await shortVisits()
        print("PASSED")
    }

    static func make(_ world: FakeWorld, _ presenter: PageRecorder, place: Bool = true,
                     symbols: String = "AAPL, BTC-USD") -> (DayModule, NotchcastContext) {
        let suite = "nc-day-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if place { defaults.set(try? JSONEncoder().encode(DayFixtures.place), forKey: DayModule.placeKey) }
        defaults.set(symbols, forKey: DayModule.symbolsKey)
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: DayAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { world.now }, onTapsChanged: {},
            calendar: NotchcastCalendar(events: { world.events }, showSchedule: { world.scheduleOpens += 1 }))
        let module = DayModule(context: context, fetch: { await world.get($0) }, sleep: { try await world.sleep($0) },
                               calendar: DayFixtures.calendar, locale: DayFixtures.locale)
        return (module, context)
    }

    static func switchShape() {
        check(DayAddon.switches.map(\.id) == ["dayPage"], "the switch id is frozen")
        let entry = DayAddon.switches[0]
        check(!entry.defaultEnabled && entry.requiredGrants.isEmpty && entry.dependencies.isEmpty,
              "off by default, and it needs no grant")
        let (_, context) = make(FakeWorld(), PageRecorder())
        check(DayAddon.makeModule(context) is DayModule, "the switch has a module as its user path")
        check(DayAddon.settings.map(\.switchID) == ["dayPage"], "its city and symbols sit under the switch")
    }

    static func nothingChosen() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter, place: false, symbols: "")
        module.stop()
        check(presenter.pages.isEmpty, "stopping a module that never ran posts nothing")
        world.steps = [{
            world.events = [NotchcastEvent(id: "a", title: "Design review", start: world.now.addingTimeInterval(1560),
                                           end: world.now.addingTimeInterval(3600), isAllDay: false)]
        }]
        module.start()
        module.start()
        presenter.watcher?(true)
        await module.loop?.value
        check(world.requests.isEmpty, "with no city and no symbols nothing is fetched")
        check(presenter.pages.count == 1 && presenter.titles(0) == ["Today", "Design review"],
              "no tab while there is nothing, then today's events alone: \(presenter.pages.count)")
        check(presenter.pages[0]?.line.text == "in 26 min · Design review", "\(presenter.pages[0]?.line.text ?? "")")
        presenter.action?(DayPage.scheduleAction)
        check(world.scheduleOpens == 1, "the calendar line opens My Schedule")
        module.stop()
        check(presenter.pages.count == 2 && presenter.pages[1] == nil, "switching off removes the page")
    }

    static func cadence() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter)
        world.steps = [
            { world.note(advance: 60) }, { world.note(advance: 239) }, { world.note(advance: 1) },
            { world.note(advance: 1500) }, { world.note() },
        ]
        module.start()
        presenter.watcher?(true)
        await module.loop?.value
        check(world.seen == [["AAPL", "BTC-USD", "weather"], [], [], ["AAPL", "BTC-USD"],
                             ["AAPL", "BTC-USD", "weather"]],
              "everything at once, markets every 5 minutes, weather every 30: \(world.seen)")
        check(Array(presenter.titles(0).prefix(2)) == ["9° Mostly Clear", "16"], "the page carries the weather")
        check(presenter.trailing(0, "AAPL") == "352.79  ▲ 0.25%", "and the quotes")
        check(presenter.pages.count == 3 && presenter.titles(1)[1] == "17",
              "an unchanged page is not posted again; an hour gone by is: \(presenter.pages.count)")
        check(presenter.trailing(1, "Markets") == "Updated 15:36" && presenter.trailing(2, "Markets") == nil,
              "quotes 25 minutes old are marked until the fetch returns")
        module.stop()
    }

    static func visibility() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter)
        module.start()
        check(presenter.watcher != nil && module.loop == nil && world.requests.isEmpty,
              "switched on with the island closed it watches, runs no timer and fetches nothing")
        world.steps = [{ world.note(advance: 600); presenter.watcher?(false) }]
        presenter.watcher?(true)
        await module.loop?.value
        check(module.loop == nil && world.seen == [["AAPL", "BTC-USD", "weather"]],
              "shown it fetches at once; hidden its timer stops: \(world.seen)")
        await module.update()
        check(world.requests.isEmpty, "hidden, a due feed is not fetched")
        world.steps = [{ world.note() }]
        presenter.watcher?(true)
        await module.loop?.value
        check(world.seen.last == ["AAPL", "BTC-USD"], "shown again it fetches only what is past its interval")
        module.stop()
        check(presenter.watcher == nil, "switching off stops watching")
    }

    static func offline() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter, symbols: "AAPL")
        world.online = false
        world.steps = [
            { world.note(advance: 59) },
            { world.note(advance: 1); world.online = true },
            { world.note(advance: 240) },
            { world.note(advance: 300); world.online = false },
            { world.note() },
        ]
        module.start()
        presenter.watcher?(true)
        await module.loop?.value
        check(world.seen == [["AAPL", "weather"], [], ["weather"], ["AAPL"], ["AAPL"]],
              "failed weather retries after a minute, failed markets after their 5: \(world.seen)")
        check(presenter.trailing(0, "Weather") == "Unavailable" && presenter.trailing(0, "Markets") == "Unavailable",
              "unavailable with nothing yet says so")
        check(presenter.trailing(2, "9° Mostly Clear") == nil && presenter.trailing(2, "Markets") == nil,
              "back online the values show with no stamp")
        let last = presenter.pages.count - 1
        check(presenter.trailing(last, "Markets") == "Updated 15:36" && presenter.trailing(last, "AAPL") != "–",
              "failing again keeps the last quotes and their time: \(presenter.trailing(last, "Markets") ?? "nil")")
        check(presenter.trailing(last, "9° Mostly Clear") == nil, "weather, not yet due, is not marked stale")
        module.stop()
    }

    static func keys() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter, symbols: "AAPL NOPE")
        module.start()
        presenter.watcher?(true)
        await module.loop?.value
        check(world.take() == ["AAPL", "NOPE", "weather"] && presenter.trailing(0, "NOPE") == "–",
              "an unknown symbol shows a dash beside the others")
        world.now += 5
        presenter.action?(IslandPage.refreshAction)
        await module.refresh?.value
        check(world.take() == ["AAPL", "NOPE", "weather"], "Command-R fetches at once, due or not")
        presenter.action?("other")
        presenter.action?(DayPage.scheduleAction)
        check(world.requests.isEmpty && world.scheduleOpens == 1, "only the refresh action fetches")
        module.setSymbols("BTC-USD")
        await module.refresh?.value
        check(world.take() == ["BTC-USD"] && presenter.titles(presenter.pages.count - 1).contains("BTC-USD")
            && !presenter.titles(presenter.pages.count - 1).contains("AAPL"), "a new list is fetched at once")
        module.stop()
    }

    static func city() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter, place: false, symbols: "")
        module.start()
        presenter.watcher?(true)
        await module.loop?.value
        world.cityKnown = false
        let missing = await module.setCity("Atlantis")
        check(!missing && module.place == nil && world.take() == ["city"], "a city nobody knows is not kept")
        world.cityKnown = true
        let found = await module.setCity(" Warsaw ")
        check(found && module.place?.name == "Warsaw" && world.take() == ["city", "weather"],
              "a found city is kept and its weather fetched at once")
        check(presenter.titles(presenter.pages.count - 1).first == "9° Mostly Clear", "and shown")
        let cleared = await module.setCity("")
        check(cleared && module.place == nil && world.requests.isEmpty && presenter.pages.last! == nil,
              "an empty city clears the weather without asking anyone")
        module.stop()
    }

    static func staleLoad() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter, symbols: "")
        world.holds = true
        module.start()
        presenter.watcher?(true)
        for _ in 0..<1000 where world.gates.isEmpty { await Task.yield() }
        check(!world.gates.isEmpty, "the load reached the network")
        let load = module.load
        module.stop()
        world.release()
        await load?.value
        check(presenter.pages == [nil], "a load that returns after the switch went off posts nothing")
    }

    /// Hiding mid-load stops only the timer: the load is recorded and posts, so short visits ask once.
    static func shortVisits() async {
        let world = FakeWorld()
        let presenter = PageRecorder()
        let (module, _) = make(world, presenter)
        world.holds = true
        module.start()
        presenter.watcher?(true)
        for _ in 0..<1000 where world.gates.count < 3 { await Task.yield() }
        check(world.gates.count == 3, "the load reached the network: \(world.gates.count)")
        for _ in 0..<10 {
            presenter.watcher?(false)
            await Task.yield()
            presenter.watcher?(true)
            await Task.yield()
        }
        presenter.watcher?(false)
        presenter.watcher?(true)
        check(world.take() == ["AAPL", "BTC-USD", "weather"], "ten short visits start the requests once")
        let load = module.load
        world.release()
        await load?.value
        check(module.load == nil && presenter.pages.last != nil
            && presenter.titles(presenter.pages.count - 1).first == "9° Mostly Clear"
            && presenter.trailing(presenter.pages.count - 1, "AAPL") == "352.79  ▲ 0.25%",
              "the load outlives the visits and posts at once")
        presenter.watcher?(false)
        presenter.watcher?(true)
        await module.loop?.value
        check(world.requests.isEmpty, "its answer is recorded, so showing again asks nothing")
        module.stop()
    }
}
