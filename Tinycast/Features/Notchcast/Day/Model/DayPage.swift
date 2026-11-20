import Foundation

/// The Day page (#978) as island values: weather, markets, today's events and its Home line.
enum DayPage {
    static let id = "day"
    /// Last, after Agents (0), Player (10) and System (20), as decision 946-11 orders them.
    static let order = 30
    /// Sent by an event row and by the Home line while it names an event: open My Schedule.
    static let scheduleAction = "schedule"
    static let unavailableSymbol = "exclamationmark.triangle"

    /// Nil while there is nothing to show, so the island keeps no empty tab.
    static func page(_ board: DayBoard, now: Date, calendar: Calendar, locale: Locale) -> IslandPage? {
        let today = DayAgenda.today(board.events, now: now, calendar: calendar)
        let blocks = weather(board, now: now, calendar: calendar, locale: locale)
            + markets(board, now: now, calendar: calendar, locale: locale)
            + events(today, now: now, calendar: calendar, locale: locale)
        guard !blocks.isEmpty else { return nil }
        return IslandPage(id: id, title: String(localized: "Day", table: "NotchcastDay"), symbol: "sun.max",
                          order: order, line: line(board, today: today, now: now, calendar: calendar, locale: locale),
                          blocks: blocks.map(IslandPageBlock.row))
    }

    /// The next event, opening My Schedule; else weather or a quote unless its last fetch failed.
    static func line(_ board: DayBoard, today: [DayEvent], now: Date, calendar: Calendar,
                     locale: Locale) -> IslandPageLine {
        let sky = board.weatherClock.isOffline ? nil : board.weather.map {
            (DayWeatherFeed.symbol($0.current), summary($0.current, locale: locale))
        }
        let quotes = board.quotesClock.isOffline ? [] : board.symbols
        let quote = quotes.lazy.compactMap { board.quotes[$0] }.first.map { quote in
            [quote.symbol, DayQuoteFeed.change(quote, locale: locale) ?? DayQuoteFeed.price(quote, locale: locale)]
                .joined(separator: " ")
        }
        if let event = DayAgenda.next(today) ?? today.first {
            let when = DayAgenda.when(event, now: now, calendar: calendar, locale: locale)
            return IslandPageLine(symbol: "calendar", text: "\(when) · \(event.title)", detail: sky?.1 ?? quote,
                                  action: scheduleAction)
        }
        if let sky { return IslandPageLine(symbol: sky.0, text: sky.1, detail: quote) }
        if let quote { return IslandPageLine(symbol: "chart.line.uptrend.xyaxis", text: quote) }
        return IslandPageLine(symbol: unavailableSymbol, text: String(localized: "Unavailable", table: "NotchcastDay"))
    }

    /// Now, then the coming hours; stale, it keeps the last reading and says when it was taken.
    static func weather(_ board: DayBoard, now: Date, calendar: Calendar, locale: Locale) -> [IslandPageRow] {
        guard let place = board.place else { return [] }
        let offline = board.weatherClock.isOffline
        guard let weather = board.weather else {
            let title = String(localized: "Weather", table: "NotchcastDay")
            return offline ? [IslandPageRow(symbol: unavailableSymbol, title: title, detail: place.name,
                                            trailing: String(localized: "Unavailable", table: "NotchcastDay"))] : []
        }
        let stamp = board.weatherIsStale(now: now) ? board.weatherClock.succeededAt.map {
            updated($0, calendar: calendar, locale: locale)
        } : nil
        let head = IslandPageRow(symbol: DayWeatherFeed.symbol(weather.current),
                                 title: summary(weather.current, locale: locale), detail: place.name,
                                 trailing: stamp)
        var style = Date.FormatStyle.dateTime.hour()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return [head] + weather.hours.filter { $0.at > now }.map {
            IslandPageRow(symbol: DayWeatherFeed.symbol($0), title: $0.at.formatted(style),
                          trailing: DayWeatherFeed.degrees($0.celsius, locale: locale))
        }
    }

    /// One row per chosen symbol under a header; a symbol with no quote yet shows a dash.
    static func markets(_ board: DayBoard, now: Date, calendar: Calendar, locale: Locale) -> [IslandPageRow] {
        let clock = board.quotesClock
        guard !board.symbols.isEmpty, !board.quotes.isEmpty || clock.isOffline else { return [] }
        let state = !board.quotesAreStale(now: now) ? nil : clock.succeededAt.map {
            updated($0, calendar: calendar, locale: locale)
        } ?? String(localized: "Unavailable", table: "NotchcastDay")
        let header = IslandPageRow(symbol: clock.isOffline && board.quotes.isEmpty ? unavailableSymbol
                                       : "chart.line.uptrend.xyaxis",
                                   title: String(localized: "Markets", table: "NotchcastDay"), trailing: state)
        return [header] + board.symbols.map { symbol in
            let quote = board.quotes[symbol]
            let parts = quote.map { [DayQuoteFeed.price($0, locale: locale), DayQuoteFeed.change($0, locale: locale)] }
            return IslandPageRow(title: symbol, trailing: parts?.compactMap { $0 }.joined(separator: "  ") ?? "–")
        }
    }

    /// Every row opens My Schedule; past `DayAgenda.limit` the rest are one counted row.
    static func events(_ today: [DayEvent], now: Date, calendar: Calendar, locale: Locale) -> [IslandPageRow] {
        guard !today.isEmpty else { return [] }
        let header = IslandPageRow(id: scheduleAction, symbol: "calendar",
                                   title: String(localized: "Today", table: "NotchcastDay"))
        let rows = today.prefix(DayAgenda.limit).map {
            IslandPageRow(id: scheduleAction, title: $0.title,
                          trailing: DayAgenda.when($0, now: now, calendar: calendar, locale: locale))
        }
        let rest = today.count - rows.count
        let more = rest > 0 ? [IslandPageRow(id: scheduleAction,
                                             title: String(localized: "\(rest) more", table: "NotchcastDay"))] : []
        return [header] + rows + more
    }

    static func summary(_ hour: DayWeatherHour, locale: Locale) -> String {
        DayWeatherFeed.degrees(hour.celsius, locale: locale) + " " + DayWeatherFeed.words(hour)
    }

    static func updated(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let time = DayAgenda.time(date, calendar: calendar, locale: locale)
        return String(localized: "Updated \(time)", table: "NotchcastDay")
    }
}
