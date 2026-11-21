// notchcast-sources: Tinycast/Features/Notchcast/Day/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tests/nc-Day-fixtures.swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Day-model-test: \(message)") }
}

/// #978's parsing, refresh and offline decisions, from fake responses and an injected clock.
@main
struct DayModelTests {
    typealias Fix = DayFixtures

    static func main() {
        weatherParsing()
        placeParsing()
        symbolList()
        quoteParsing()
        refreshClock()
        board()
        visibility()
        quoteRound()
        agenda()
        page()
        offlinePage()
        staleLine()
        agedPage()
        print("PASSED")
    }

    static func weatherParsing() {
        guard let weather = DayWeatherFeed.weather(from: Fix.forecast) else {
            fatalError("nc-Day-model-test: forecast")
        }
        check(weather.current.celsius == 9.2 && weather.current.code == 1 && !weather.current.isDay, "the reading now")
        check(weather.hours.count == DayWeatherFeed.hourCount, "five coming hours: \(weather.hours.count)")
        check(weather.hours[0].at == Date(timeIntervalSince1970: 1_795_017_600) && weather.hours[0].celsius == 8.8,
              "the hour already under way is left out")
        check(DayWeatherFeed.weather(from: Data("not json".utf8)) == nil, "garbage is no weather")
        let short = Fix.forecastText.replacingOccurrences(of: ",7.4]", with: "]")
        check(DayWeatherFeed.weather(from: Data(short.utf8)) == nil, "hourly lists of unequal length are refused")
        let boiling = Fix.forecastText.replacingOccurrences(of: "9.2", with: "920")
        check(DayWeatherFeed.weather(from: Data(boiling.utf8)) == nil, "an impossible temperature is refused")

        check(DayWeatherFeed.symbol(weather.current) == "cloud.moon" && DayWeatherFeed.words(weather.current)
            == "Mostly Clear", "code 1 at night")
        let storm = DayWeatherHour(at: Fix.now, celsius: 20, code: 95, isDay: true)
        check(DayWeatherFeed.symbol(storm) == "cloud.bolt.rain" && DayWeatherFeed.words(storm) == "Thunderstorm", "95")
        let odd = DayWeatherHour(at: Fix.now, celsius: 20, code: 1234, isDay: true)
        check(DayWeatherFeed.symbol(odd) == "thermometer.medium", "an unknown code still has a glyph")
        check(DayWeatherFeed.degrees(9.2, locale: Fix.locale) == "9°", "whole degrees")
        check(DayWeatherFeed.degrees(-0.4, locale: Fix.locale) == "0°", "no minus zero")
        check(DayWeatherFeed.degrees(10, locale: Locale(identifier: "en_US")) == "50°", "Fahrenheit where it is used")
        let url = DayWeatherFeed.forecastURL(Fix.place)?.absoluteString ?? ""
        check(url.hasPrefix("https://api.open-meteo.com/v1/forecast?latitude=52.23&longitude=21.01&"), url)
    }

    static func placeParsing() {
        check(DayWeatherFeed.place(from: Fix.search)
            == DayPlace(name: "Warsaw", latitude: 52.22977, longitude: 21.01178), "the first match")
        check(DayWeatherFeed.place(from: Fix.noCity) == nil, "no match is no place")
        let offGlobe = Fix.searchText.replacingOccurrences(of: "52.22977", with: "152")
        check(DayWeatherFeed.place(from: Data(offGlobe.utf8)) == nil, "a latitude off the globe is refused")
        check(DayWeatherFeed.searchURL("  ") == nil, "an empty city asks nothing")
        check(DayWeatherFeed.searchURL("New York")?.absoluteString.contains("name=New%20York") == true, "encoded")
    }

    static func symbolList() {
        check(DayQuoteFeed.symbols(from: " aapl, btc-usd;EURUSD=X aapl ^gspc bad$ym waytoolongsymbolname1234 ")
            == ["AAPL", "BTC-USD", "EURUSD=X", "^GSPC"], "upper case, no repeats, nothing a symbol cannot hold")
        check(DayQuoteFeed.symbols(from: "A B C D E F G H I J").count == DayQuoteFeed.symbolLimit, "at most eight")
        check(DayQuoteFeed.url(for: "^GSPC")?.absoluteString
            == "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?interval=1d&range=1d", "the caret is encoded")
        check(DayQuoteFeed.url(for: "EURUSD=X")?.absoluteString.contains("/EURUSD%3DX?") == true, "so is the equals")
    }

    static func quoteParsing() {
        let apple = DayQuoteFeed.quote(from: Fix.chart("AAPL", price: 352.79, change: 0.25), symbol: "AAPL")
        check(apple == DayQuote(symbol: "AAPL", price: 352.79, changePercent: 0.25, decimals: 2), "a stock")
        check(DayQuoteFeed.quote(from: Fix.chart("MSFT", price: 1, change: 0), symbol: "AAPL") == nil,
              "an answer for another symbol is refused")
        check(DayQuoteFeed.quote(from: Fix.unknownSymbol, symbol: "NOPE") == nil, "an unknown symbol has no quote")
        check(DayQuoteFeed.quote(from: Fix.chart("AAPL", price: 0, change: 0), symbol: "AAPL") == nil, "no price")
        let fromClose = DayQuoteFeed.quote(from: Fix.chart("AAPL", price: 101, change: nil, close: 100), symbol: "AAPL")
        check(abs((fromClose?.changePercent ?? 0) - 1) < 0.0001, "the change falls back to the previous close")
        let bare = DayQuoteFeed.quote(from: Fix.chart("AAPL", price: 101, change: nil), symbol: "AAPL")
        check(bare != nil && bare?.changePercent == nil, "a price with no change still shows")

        let coin = DayQuote(symbol: "BTC-USD", price: 63145.62, changePercent: -1.408, decimals: 2)
        let pair = DayQuote(symbol: "EURUSD=X", price: 1.0969, changePercent: 0.001, decimals: 4)
        check(DayQuoteFeed.price(coin, locale: Fix.locale) == "63,145.62", DayQuoteFeed.price(coin, locale: Fix.locale))
        check(DayQuoteFeed.price(pair, locale: Fix.locale) == "1.0969", "a currency keeps its four places")
        check(DayQuoteFeed.change(apple!, locale: Fix.locale) == "▲ 0.25%", "up, with its arrow")
        check(DayQuoteFeed.change(coin, locale: Fix.locale) == "▼ 1.41%", "down, with its arrow")
        check(DayQuoteFeed.change(pair, locale: Fix.locale) == "0.00%", "flat has no arrow")
        check(DayQuoteFeed.change(bare!, locale: Fix.locale) == nil, "no change, no text")
    }

    static func refreshClock() {
        var clock = DayFeedClock()
        check(clock.isDue(now: Fix.now, every: 300, retry: 60) && !clock.isOffline, "a new feed is due and not offline")
        clock.record(success: true, at: Fix.now)
        check(!clock.isDue(now: Fix.now.addingTimeInterval(299), every: 300, retry: 60), "fresh inside the interval")
        check(clock.isDue(now: Fix.now.addingTimeInterval(300), every: 300, retry: 60), "due at the interval")
        check(clock.isDue(now: Fix.now.addingTimeInterval(-10), every: 300, retry: 60), "a clock set back is due")
        clock.record(success: false, at: Fix.now.addingTimeInterval(300))
        check(clock.isOffline && clock.succeededAt == Fix.now, "a failure is offline and keeps the last good time")
        check(!clock.isDue(now: Fix.now.addingTimeInterval(359), every: 300, retry: 60), "a failure waits its retry")
        check(clock.isDue(now: Fix.now.addingTimeInterval(360), every: 300, retry: 60), "then asks again")
        clock.record(success: true, at: Fix.now.addingTimeInterval(360))
        check(!clock.isOffline, "a success ends offline")
        let fresh = Fix.now.addingTimeInterval(360)
        check(!clock.isStale(now: fresh.addingTimeInterval(299), after: 300)
            && clock.isStale(now: fresh.addingTimeInterval(300), after: 300), "an answer goes stale with age")
    }

    static func board() {
        var board = DayBoard()
        board.isVisible = true
        check(!board.weatherIsDue(now: Fix.now) && !board.quotesAreDue(now: Fix.now), "nothing chosen, nothing asked")
        board.configure(place: Fix.place, symbols: ["AAPL", "BTC-USD"])
        check(board.weatherIsDue(now: Fix.now) && board.quotesAreDue(now: Fix.now), "a new place and list are due")
        board.apply(weather: Fix.forecast, at: Fix.now)
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25), "BTC-USD": Fix.unknownSymbol],
                    at: Fix.now)
        check(board.weather != nil && !board.weatherClock.isOffline, "weather applied")
        check(board.quotes.keys.sorted() == ["AAPL"] && !board.quotesClock.isOffline, "one good quote means online")
        check(!board.weatherIsDue(now: Fix.now.addingTimeInterval(DayBoard.weatherInterval - 1))
            && board.weatherIsDue(now: Fix.now.addingTimeInterval(DayBoard.weatherInterval)), "weather every 30 min")
        check(!board.quotesAreDue(now: Fix.now.addingTimeInterval(DayBoard.quotesInterval - 1))
            && board.quotesAreDue(now: Fix.now.addingTimeInterval(DayBoard.quotesInterval)), "markets every 5 min")

        let later = Fix.now.addingTimeInterval(DayBoard.quotesInterval)
        board.apply(weather: nil, at: later)
        board.apply(quotes: [:], at: later)
        check(board.weather != nil && board.weatherClock.isOffline, "offline keeps the last weather")
        check(board.quotes["AAPL"] != nil && board.quotesClock.isOffline, "and the last quotes")
        check(board.weatherIsDue(now: later.addingTimeInterval(DayBoard.retryInterval)), "and retries soon")
        board.apply(weather: Data("{}".utf8), at: later)
        check(board.weatherClock.isOffline, "an answer that does not parse is a failure")

        board.configure(place: Fix.place, symbols: ["AAPL", "BTC-USD"])
        check(board.weather != nil, "the same settings change nothing")
        board.configure(place: DayPlace(name: "Oslo", latitude: 59.9, longitude: 10.7), symbols: ["BTC-USD"])
        check(board.weather == nil && board.weatherClock == DayFeedClock(), "a new place starts weather over")
        check(board.quotes.isEmpty && board.quotesClock == DayFeedClock(), "a dropped symbol takes its quote along")
    }

    /// Decision 946: fetched only while Home or Day shows; shown again, what is past its interval is due.
    static func visibility() {
        var board = DayBoard()
        board.configure(place: Fix.place, symbols: ["AAPL"])
        check(!board.weatherIsDue(now: Fix.now) && !board.quotesAreDue(now: Fix.now), "hidden, nothing is due")
        board.isVisible = true
        check(board.weatherIsDue(now: Fix.now) && board.quotesAreDue(now: Fix.now), "shown, new feeds are due")
        board.apply(weather: Fix.forecast, at: Fix.now)
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25)], at: Fix.now)
        board.isVisible = false
        let back = Fix.now.addingTimeInterval(10 * 60)
        check(!board.weatherIsDue(now: back.addingTimeInterval(3600)) && !board.quotesAreDue(now: back),
              "hidden, a feed past its interval still waits")
        board.isVisible = true
        check(board.quotesAreDue(now: back) && !board.weatherIsDue(now: back),
              "shown after 10 minutes: markets are due, weather is still fresh")
        check(board.weatherIsDue(now: Fix.now.addingTimeInterval(DayBoard.weatherInterval)), "and after 30 so is it")
    }

    /// A good round replaces every quote; only a round with no good answer keeps the last ones.
    static func quoteRound() {
        var board = DayBoard()
        board.isVisible = true
        board.configure(place: nil, symbols: ["AAPL", "BTC-USD"])
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25),
                             "BTC-USD": Fix.chart("BTC-USD", price: 63145.62, change: -1.408)], at: Fix.now)
        let later = Fix.now.addingTimeInterval(DayBoard.quotesInterval)
        board.apply(quotes: ["AAPL": Fix.unknownSymbol, "BTC-USD": Fix.chart("BTC-USD", price: 64000, change: 1)],
                    at: later)
        check(board.quotes.keys.sorted() == ["BTC-USD"] && board.quotes["BTC-USD"]?.price == 64000
            && !board.quotesClock.isOffline, "a symbol that fails in a good round drops its old price")
        board.apply(quotes: [:], at: later.addingTimeInterval(DayBoard.quotesInterval))
        check(board.quotes["BTC-USD"]?.price == 64000 && board.quotesClock.isOffline, "a failed round keeps them")
        let failed = later.addingTimeInterval(DayBoard.quotesInterval)
        check(!board.quotesAreDue(now: failed.addingTimeInterval(DayBoard.quotesInterval - 1))
            && board.quotesAreDue(now: failed.addingTimeInterval(DayBoard.quotesInterval)),
              "markets retry after their own interval, not every minute")
    }

    static func agenda() {
        let events = [
            Fix.event("late", "Dinner", from: 2 * 3600 + 1740),
            Fix.event("soon", "Design review", from: 25 * 60),
            Fix.event("soon", "Design review", from: 25 * 60),
            Fix.event("over", "Stand-up", from: -3600),
            Fix.event("ending", "Ends now", from: -1800),
            Fix.event("running", "Workshop", from: -600, for: 3600),
            Fix.event("tomorrow", "Dentist", from: 20 * 3600),
            Fix.event("empty", "Nothing", from: 600, for: 0),
            DayEvent(id: "day", title: "Conference", start: Fix.calendar.startOfDay(for: Fix.now),
                     end: Fix.calendar.startOfDay(for: Fix.now).addingTimeInterval(86400), isAllDay: true),
            DayEvent(id: "yesterday", title: "Holiday", start: Fix.calendar.startOfDay(for: Fix.now) - 86400,
                     end: Fix.calendar.startOfDay(for: Fix.now), isAllDay: true),
        ]
        let today = DayAgenda.today(events, now: Fix.now, calendar: Fix.calendar)
        check(today.map(\.id) == ["day", "running", "soon", "late"],
              "today, not over, all-day first: \(today.map(\.id))")
        check(DayAgenda.next(today)?.id == "running", "the event under way is the next one")
        let when = today.map { DayAgenda.when($0, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale) }
        check(when == ["All day", "Now", "in 25 min", "18:00"], "\(when)")
        let seconds = Fix.event("x", "X", from: 20)
        check(DayAgenda.when(seconds, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale) == "in 1 min",
              "under a minute still counts one")
    }

    static func rows(_ page: IslandPage?) -> [IslandPageRow] {
        (page?.blocks ?? []).compactMap { if case .row(let row) = $0 { row } else { nil } }
    }

    static func loaded() -> DayBoard {
        var board = DayBoard()
        board.configure(place: Fix.place, symbols: ["AAPL", "BTC-USD", "EURUSD=X"])
        board.apply(weather: Fix.forecast, at: Fix.now)
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25),
                             "BTC-USD": Fix.chart("BTC-USD", price: 63145.62, change: -1.408)], at: Fix.now)
        return board
    }

    static func page() {
        check(DayPage.page(DayBoard(), now: Fix.now, calendar: Fix.calendar, locale: Fix.locale) == nil,
              "nothing to show leaves no tab")
        var board = loaded()
        let quiet = DayPage.page(board, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale)
        check(quiet?.id == DayPage.id && quiet?.order == 30 && quiet?.badge == 0, "the Day page, last, never badged")
        check(quiet?.line == IslandPageLine(symbol: "cloud.moon", text: "9° Mostly Clear", detail: "AAPL ▲ 0.25%"),
              "with no event Home shows the weather and opens the page")
        var all = rows(quiet)
        check(all[0] == IslandPageRow(symbol: "cloud.moon", title: "9° Mostly Clear", detail: "Warsaw"), "now")
        check(all[1...5].map(\.title) == ["16", "17", "18", "19", "20"], "five hours: \(all[1...5].map(\.title))")
        check(all[1...5].map(\.trailing) == ["9°", "8°", "8°", "9°", "9°"], "\(all[1...5].map(\.trailing))")
        check(all[6].title == "Markets" && all[6].trailing == nil, "the markets header, online")
        check(all[7] == IslandPageRow(title: "AAPL", trailing: "352.79  ▲ 0.25%"), "\(all[7])")
        check(all[8].trailing == "63,145.62  ▼ 1.41%" && all[9] == IslandPageRow(title: "EURUSD=X", trailing: "–"),
              "a symbol with no quote shows a dash")
        check(all.count == 10 && all.allSatisfy { $0.id == nil }, "no event rows, nothing to click")

        board.events = (0..<7).map { Fix.event("e\($0)", $0 == 0 ? "Design review" : "Event \($0)",
                                              from: 25 * 60 + Double($0) * 600) }
        let busy = DayPage.page(board, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale)
        check(busy?.line == IslandPageLine(symbol: "calendar", text: "in 25 min · Design review",
                                           detail: "9° Mostly Clear", action: DayPage.scheduleAction),
              "the calendar line opens My Schedule: \(String(describing: busy?.line))")
        all = Array(rows(busy).dropFirst(10))
        check(all.map(\.title) == ["Today", "Design review", "Event 1", "Event 2", "Event 3", "Event 4", "2 more"],
              "\(all.map(\.title))")
        check(all.allSatisfy { $0.id == DayPage.scheduleAction }, "every event row opens My Schedule")
        check(all[1].trailing == "in 25 min" && all[5].trailing == "16:36", "\(all.map(\.trailing))")

        var eventsOnly = DayBoard()
        eventsOnly.events = [Fix.event("a", "Design review", from: 25 * 60)]
        let page = DayPage.page(eventsOnly, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale)
        check(rows(page).map(\.title) == ["Today", "Design review"] && page?.line.detail == nil, "events alone")
    }

    /// Home never shows a stale reading as live: a failed feed drops out of the line.
    static func staleLine() {
        var board = loaded()
        let later = Fix.now.addingTimeInterval(DayBoard.weatherInterval)
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25)], at: later - 60)
        board.apply(weather: nil, at: later)
        var line = DayPage.page(board, now: later, calendar: Fix.calendar, locale: Fix.locale)?.line
        check(line == IslandPageLine(symbol: "chart.line.uptrend.xyaxis", text: "AAPL ▲ 0.25%"),
              "stale weather gives way to a live quote: \(String(describing: line))")
        board.events = [Fix.event("a", "Design review", from: DayBoard.weatherInterval + 25 * 60)]
        line = DayPage.page(board, now: later, calendar: Fix.calendar, locale: Fix.locale)?.line
        check(line?.detail == "AAPL ▲ 0.25%", "and is no event's detail: \(String(describing: line))")
        board.events = []
        board.apply(quotes: [:], at: later)
        line = DayPage.page(board, now: later, calendar: Fix.calendar, locale: Fix.locale)?.line
        check(line == IslandPageLine(symbol: DayPage.unavailableSymbol, text: "Unavailable"),
              "both stale, Home says so: \(String(describing: line))")
    }

    /// A reading past its interval and one tick is marked old on the page until a new answer.
    static func agedPage() {
        func markets(_ rows: [IslandPageRow]) -> String? { rows.first { $0.title == "Markets" }?.trailing }
        var board = loaded()
        let fresh = Fix.now.addingTimeInterval(DayBoard.quotesInterval + DayBoard.staleGrace - 1)
        var all = rows(DayPage.page(board, now: fresh, calendar: Fix.calendar, locale: Fix.locale))
        check(all[0].trailing == nil && markets(all) == nil,
              "inside interval and tick nothing is marked: \(all.map(\.trailing))")
        let marketsOld = fresh.addingTimeInterval(1)
        var page = DayPage.page(board, now: marketsOld, calendar: Fix.calendar, locale: Fix.locale)
        all = rows(page)
        check(all[0].trailing == nil && markets(all) == "Updated 15:31",
              "old quotes carry their time, weather is still fresh: \(all.map(\.trailing))")
        check(page?.line == IslandPageLine(symbol: "cloud.moon", text: "9° Mostly Clear", detail: "AAPL ▲ 0.25%"),
              "and stay on the Home line: \(String(describing: page?.line))")
        let allOld = Fix.now.addingTimeInterval(DayBoard.weatherInterval + DayBoard.staleGrace)
        page = DayPage.page(board, now: allOld, calendar: Fix.calendar, locale: Fix.locale)
        check(rows(page)[0].trailing == "Updated 15:31", "old weather carries its time")
        let nextDay = DayPage.page(board, now: Fix.now.addingTimeInterval(86_400), calendar: Fix.calendar,
                                   locale: Fix.locale)
        check(rows(nextDay)[0].trailing == "Updated 18 Nov at 15:31",
              "a reading from another day names it (#1173): \(String(describing: rows(nextDay).first?.trailing))")
        check(page?.line == IslandPageLine(symbol: "cloud.moon", text: "9° Mostly Clear", detail: "AAPL ▲ 0.25%"),
              "old is not failed: Home keeps both: \(String(describing: page?.line))")
        board.apply(weather: Fix.forecast, at: allOld)
        board.apply(quotes: ["AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25)], at: allOld)
        all = rows(DayPage.page(board, now: allOld, calendar: Fix.calendar, locale: Fix.locale))
        check(all[0].trailing == nil && markets(all) == nil,
              "a new answer clears the marks: \(all.map(\.trailing))")
    }

    static func offlinePage() {
        var never = DayBoard()
        never.configure(place: Fix.place, symbols: ["AAPL"])
        never.apply(weather: nil, at: Fix.now)
        never.apply(quotes: [:], at: Fix.now)
        let blank = DayPage.page(never, now: Fix.now, calendar: Fix.calendar, locale: Fix.locale)
        check(rows(blank) == [
            IslandPageRow(symbol: DayPage.unavailableSymbol, title: "Weather", detail: "Warsaw", trailing: "Unavailable"),
            IslandPageRow(symbol: DayPage.unavailableSymbol, title: "Markets", trailing: "Unavailable"),
            IslandPageRow(title: "AAPL", trailing: "–"),
        ], "offline before any answer says so: \(rows(blank))")
        check(blank?.line == IslandPageLine(symbol: DayPage.unavailableSymbol, text: "Unavailable"), "and so does Home")

        var board = loaded()
        let later = Fix.now.addingTimeInterval(2 * 3600)
        board.apply(weather: nil, at: later)
        board.apply(quotes: [:], at: later)
        let stale = rows(DayPage.page(board, now: later, calendar: Fix.calendar, locale: Fix.locale))
        check(stale[0] == IslandPageRow(symbol: "cloud.moon", title: "9° Mostly Clear", detail: "Warsaw",
                                        trailing: "Updated 15:31"), "the last weather with its time: \(stale[0])")
        check(stale[1...3].map(\.title) == ["18", "19", "20"], "hours already past drop off: \(stale.map(\.title))")
        check(stale[4].title == "Markets" && stale[4].trailing == "Updated 15:31", "the last quotes with their time")
        check(stale[5].trailing == "352.79  ▲ 0.25%", "and their last values")
    }
}
