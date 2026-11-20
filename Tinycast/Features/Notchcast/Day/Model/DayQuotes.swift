import Foundation

/// A market price and its change since the previous close, in percent.
struct DayQuote: Equatable, Sendable {
    var symbol: String
    var price: Double
    var changePercent: Double?
    /// Fraction digits the market quotes this price in.
    var decimals: Int
}

/// Yahoo Finance's keyless chart endpoint: stocks, crypto and currencies under one symbol scheme.
enum DayQuoteFeed {
    static let symbolLimit = 8
    static let symbolLength = 16
    private static let symbolCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-=^")
    private static let pathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")

    /// The user's list, split on commas and spaces: upper case, no repeats, valid symbols only.
    static func symbols(from text: String) -> [String] {
        var seen = Set<String>()
        let words = text.uppercased().split { $0 == "," || $0 == ";" || $0.isWhitespace }.map(String.init)
        return Array(words.filter {
            $0.count <= symbolLength && $0.unicodeScalars.allSatisfy(symbolCharacters.contains)
                && seen.insert($0).inserted
        }.prefix(symbolLimit))
    }

    static func url(for symbol: String) -> URL? {
        guard let path = symbol.addingPercentEncoding(withAllowedCharacters: pathCharacters) else { return nil }
        return URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(path)?interval=1d&range=1d")
    }

    private struct Answer: Decodable {
        struct Chart: Decodable {
            let result: [Result]?
        }
        struct Result: Decodable {
            let meta: Meta
        }
        struct Meta: Decodable {
            let symbol: String
            let regularMarketPrice: Double
            let regularMarketChangePercent: Double?
            let chartPreviousClose: Double?
            let priceHint: Int?
        }
        let chart: Chart
    }

    /// Nil unless the answer is for `symbol` and carries a real price.
    static func quote(from data: Data, symbol: String) -> DayQuote? {
        guard let meta = (try? JSONDecoder().decode(Answer.self, from: data))?.chart.result?.first?.meta,
              meta.symbol.uppercased() == symbol, meta.regularMarketPrice.isFinite, meta.regularMarketPrice > 0
        else { return nil }
        let fromClose = meta.chartPreviousClose.flatMap { $0 > 0 ? (meta.regularMarketPrice / $0 - 1) * 100 : nil }
        let change = (meta.regularMarketChangePercent ?? fromClose).flatMap { $0.isFinite ? $0 : nil }
        return DayQuote(symbol: symbol, price: meta.regularMarketPrice, changePercent: change,
                        decimals: min(max(meta.priceHint ?? 2, 0), 6))
    }

    static func price(_ quote: DayQuote, locale: Locale) -> String {
        quote.price.formatted(.number.precision(.fractionLength(quote.decimals)).locale(locale))
    }

    /// The change with its arrow, so direction never rests on colour: "▲ 0.25%".
    static func change(_ quote: DayQuote, locale: Locale) -> String? {
        guard let change = quote.changePercent else { return nil }
        let percent = (abs(change) / 100).formatted(.percent.precision(.fractionLength(2)).locale(locale))
        let rounded = (change * 100).rounded() / 100
        return rounded == 0 ? percent : (rounded > 0 ? "▲ " : "▼ ") + percent
    }
}
