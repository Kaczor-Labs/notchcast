import Foundation

/// Keeps the Day page current while the switch is on: a minute tick, and a fetch when a feed is due.
@MainActor
final class DayModule: NotchcastModule {
    /// Countdowns ("in 25 min") move by the minute, and no feed is due more often.
    static let tick: Duration = .seconds(60)
    static let placeKey = "dayPlace"
    static let symbolsKey = "daySymbols"

    private let context: NotchcastContext
    private let fetch: @Sendable (URL) async -> Data?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let calendar: Calendar
    private let locale: Locale
    private var board = DayBoard()
    private var posted: IslandPage?
    private var run = 0
    private var isLoading = false
    private(set) var loop: Task<Void, Never>?
    private(set) var refresh: Task<Void, Never>?

    init(context: NotchcastContext, fetch: @escaping @Sendable (URL) async -> Data? = DayNetwork.body(of:),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.context = context
        self.fetch = fetch
        self.sleep = sleep
        self.calendar = calendar
        self.locale = locale
    }

    var place: DayPlace? {
        context.defaults.data(forKey: Self.placeKey).flatMap { try? JSONDecoder().decode(DayPlace.self, from: $0) }
    }

    var symbolsText: String { context.defaults.string(forKey: Self.symbolsKey) ?? "" }

    func start() {
        guard loop == nil else { return }
        let sleep = sleep
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.update()
                if self == nil { return }
                do { try await sleep(Self.tick) } catch { return }
            }
        }
    }

    func stop() {
        guard loop != nil else { return }
        loop?.cancel()
        loop = nil
        refresh?.cancel()
        refresh = nil
        run += 1
        isLoading = false
        board = DayBoard()
        posted = nil
        context.presenter.setPage(nil, id: DayPage.id, onAction: nil)
    }

    /// Looks the city up and keeps where it is; false when no such place was found. Empty clears it.
    func setCity(_ name: String) async -> Bool {
        guard let url = DayWeatherFeed.searchURL(name) else {
            context.defaults.removeObject(forKey: Self.placeKey)
            await update()
            return true
        }
        let run = run
        let found = await fetch(url).flatMap(DayWeatherFeed.place(from:))
        guard run == self.run, let found, let data = try? JSONEncoder().encode(found) else { return false }
        context.defaults.set(data, forKey: Self.placeKey)
        await update()
        return true
    }

    func setSymbols(_ text: String) {
        context.defaults.set(text, forKey: Self.symbolsKey)
        refresh = Task { [weak self] in await self?.update() }
    }

    /// Redraws from what it has, then fetches what is due; `force` is Command-R. One load at a time.
    func update(force: Bool = false) async {
        guard loop != nil else { return }
        board.configure(place: place, symbols: DayQuoteFeed.symbols(from: symbolsText))
        post()
        let now = context.now()
        let place = board.place
        let symbols = board.symbols
        let wantsWeather = place != nil && (force || board.weatherIsDue(now: now))
        let wantsQuotes = !symbols.isEmpty && (force || board.quotesAreDue(now: now))
        guard wantsWeather || wantsQuotes, !isLoading else { return }
        isLoading = true
        let run = run
        let fetch = fetch
        async let forecast = wantsWeather ? Self.body(place.flatMap(DayWeatherFeed.forecastURL), fetch) : nil
        async let prices = wantsQuotes ? Self.bodies(symbols, fetch) : [:]
        let (weatherData, quoteData) = await (forecast, prices)
        // A load that returns after `stop` belongs to no run; one for an old place or list is dropped.
        guard run == self.run else { return }
        isLoading = false
        let done = context.now()
        if wantsWeather, board.place == place { board.apply(weather: weatherData, at: done) }
        if wantsQuotes, board.symbols == symbols { board.apply(quotes: quoteData, at: done) }
        post()
    }

    private func post() {
        board.events = context.calendar.events().map {
            DayEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
        }
        let page = DayPage.page(board, now: context.now(), calendar: calendar, locale: locale)
        // The island redraws on every post, so an unchanged page is not sent again.
        guard page != posted else { return }
        posted = page
        context.presenter.setPage(page, id: DayPage.id) { [weak self] action in
            guard let self else { return }
            switch action {
            case IslandPage.refreshAction: self.refresh = Task { [weak self] in await self?.update(force: true) }
            case DayPage.scheduleAction: self.context.calendar.showSchedule()
            default: break
            }
        }
    }

    private nonisolated static func body(_ url: URL?, _ fetch: @Sendable (URL) async -> Data?) async -> Data? {
        guard let url else { return nil }
        return await fetch(url)
    }

    private nonisolated static func bodies(_ symbols: [String],
                                           _ fetch: @escaping @Sendable (URL) async -> Data?) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for symbol in symbols {
                group.addTask { (symbol, await body(DayQuoteFeed.url(for: symbol), fetch)) }
            }
            var found: [String: Data] = [:]
            for await (symbol, data) in group { found[symbol] = data }
            return found
        }
    }
}
