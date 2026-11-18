import Foundation

/// One feed's clock: when it was last asked and when that last worked.
struct DayFeedClock: Equatable, Sendable {
    private(set) var attemptedAt: Date?
    private(set) var succeededAt: Date?

    /// The last request failed, so what shows is older than it looks.
    var isOffline: Bool { attemptedAt != nil && attemptedAt != succeededAt }

    /// Due at first, `interval` after a success and `retry` after a failure; a clock set back is due.
    func isDue(now: Date, every interval: TimeInterval, retry: TimeInterval) -> Bool {
        guard let attemptedAt else { return true }
        let age = now.timeIntervalSince(attemptedAt)
        return age < 0 || age >= (isOffline ? retry : interval)
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
    /// Shorter after a failure, so a Mac back online catches up soon.
    static let retryInterval: TimeInterval = 60

    var place: DayPlace?
    var weather: DayWeather?
    var weatherClock = DayFeedClock()
    var symbols: [String] = []
    var quotes: [String: DayQuote] = [:]
    var quotesClock = DayFeedClock()
    var events: [DayEvent] = []

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
        place != nil && weatherClock.isDue(now: now, every: Self.weatherInterval, retry: Self.retryInterval)
    }

    func quotesAreDue(now: Date) -> Bool {
        !symbols.isEmpty && quotesClock.isDue(now: now, every: Self.quotesInterval, retry: Self.retryInterval)
    }

    /// An answer that does not parse counts as a failure and keeps the last weather.
    mutating func apply(weather data: Data?, at now: Date) {
        let parsed = data.flatMap(DayWeatherFeed.weather(from:))
        if let parsed { weather = parsed }
        weatherClock.record(success: parsed != nil, at: now)
    }

    /// Each symbol keeps its last quote until a new one parses; one good answer means online.
    mutating func apply(quotes data: [String: Data], at now: Date) {
        var parsed = 0
        for symbol in symbols {
            guard let quote = data[symbol].flatMap({ DayQuoteFeed.quote(from: $0, symbol: symbol) }) else { continue }
            quotes[symbol] = quote
            parsed += 1
        }
        quotesClock.record(success: parsed > 0, at: now)
    }
}
