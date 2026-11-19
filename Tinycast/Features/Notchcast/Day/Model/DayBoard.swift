import Foundation

/// One feed's clock: when it was last asked and when that last worked.
struct DayFeedClock: Equatable, Sendable {
    private(set) var attemptedAt: Date?
    private(set) var succeededAt: Date?

    /// The last request failed, so what shows is older than it looks.
    var isOffline: Bool { attemptedAt != nil && attemptedAt != succeededAt }

    /// Due at first, `interval` after a success, `retry` after a failure; a clock set back is due.
    func isDue(now: Date, every interval: TimeInterval, retry: TimeInterval) -> Bool {
        guard let attemptedAt else { return true }
        let age = now.timeIntervalSince(attemptedAt)
        return age < 0 || age >= (isOffline ? retry : interval)
    }

    /// Older than it looks: the last request failed, or its last answer is `after` seconds old.
    func isStale(now: Date, after age: TimeInterval) -> Bool {
        isOffline || succeededAt.map { now.timeIntervalSince($0) >= age } ?? false
    }

    mutating func record(success: Bool, at now: Date) {
        attemptedAt = now
        if success { succeededAt = now }
    }
}

/// Everything the Day page is drawn from.
struct DayBoard: Equatable, Sendable {
    /// Decision 946: weather every 30 minutes, markets every 5.
    static let weatherInterval: TimeInterval = 30 * 60
    static let quotesInterval: TimeInterval = 5 * 60
    /// Weather is one request, so it may retry sooner after a failure; markets wait their interval.
    static let retryInterval: TimeInterval = 60
    /// A shown page asks again within a minute tick, so only a reading past that is marked old.
    static let staleGrace: TimeInterval = 60

    var place: DayPlace?
    var weather: DayWeather?
    var weatherClock = DayFeedClock()
    var symbols: [String] = []
    var quotes: [String: DayQuote] = [:]
    var quotesClock = DayFeedClock()
    var events: [DayEvent] = []
    /// Decision 946: feeds are fetched only while the open island shows Home or the Day page.
    var isVisible = false

    /// A new place or list starts its feed over; nothing of the old one stays on the page.
    mutating func configure(place: DayPlace?, symbols: [String]) {
        if place != self.place {
            self.place = place
            weather = nil
            weatherClock = DayFeedClock()
        }
        if symbols != self.symbols {
            self.symbols = symbols
            quotes = quotes.filter { symbols.contains($0.key) }
            quotesClock = DayFeedClock()
        }
    }

    func weatherIsDue(now: Date) -> Bool {
        isVisible && place != nil
            && weatherClock.isDue(now: now, every: Self.weatherInterval, retry: Self.retryInterval)
    }

    func quotesAreDue(now: Date) -> Bool {
        isVisible && !symbols.isEmpty
            && quotesClock.isDue(now: now, every: Self.quotesInterval, retry: Self.quotesInterval)
    }

    func weatherIsStale(now: Date) -> Bool {
        weatherClock.isStale(now: now, after: Self.weatherInterval + Self.staleGrace)
    }

    func quotesAreStale(now: Date) -> Bool {
        quotesClock.isStale(now: now, after: Self.quotesInterval + Self.staleGrace)
    }

    /// An answer that does not parse counts as a failure and keeps the last weather.
    mutating func apply(weather data: Data?, at now: Date) {
        let parsed = data.flatMap(DayWeatherFeed.weather(from:))
        if let parsed { weather = parsed }
        weatherClock.record(success: parsed != nil, at: now)
    }

    /// A symbol that fails in a good round shows a dash; a round with no answer keeps them all.
    mutating func apply(quotes data: [String: Data], at now: Date) {
        let parsed = symbols.compactMap { symbol in
            data[symbol].flatMap { DayQuoteFeed.quote(from: $0, symbol: symbol) }
        }
        let success = !parsed.isEmpty
        if success { quotes = Dictionary(parsed.map { ($0.symbol, $0) }, uniquingKeysWith: { $1 }) }
        quotesClock.record(success: success, at: now)
    }
}
