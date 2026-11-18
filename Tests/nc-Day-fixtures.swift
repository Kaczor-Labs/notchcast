import Foundation

/// Answers shaped like the live ones (Open-Meteo forecast and search, Yahoo chart), cut to what is read.
enum DayFixtures {
    /// 15:31 UTC, a minute after the forecast's current reading.
    static let now = Date(timeIntervalSince1970: 1_795_015_860)
    static let locale = Locale(identifier: "en_GB")
    static let place = DayPlace(name: "Warsaw", latitude: 52.23, longitude: 21.01)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }

    static let forecast = Data(forecastText.utf8)
    static let search = Data(searchText.utf8)

    static let forecastText = """
        {"latitude":52.23,"longitude":21.01,"utc_offset_seconds":0,
         "current":{"time":1795015800,"interval":900,"temperature_2m":9.2,"weather_code":1,"is_day":0},
         "hourly":{"time":[1795014000,1795017600,1795021200,1795024800,1795028400,1795032000,1795035600],
                   "temperature_2m":[9.5,8.8,8.2,8.1,9.0,8.6,7.4],
                   "weather_code":[2,0,3,53,3,51,95],"is_day":[0,0,0,0,0,0,0]}}
        """

    static let searchText = """
        {"results":[{"id":756135,"name":"Warsaw","latitude":52.22977,"longitude":21.01178,"country":"Poland"}],
         "generationtime_ms":0.12}
        """

    static let noCity = Data(#"{"generationtime_ms":0.1}"#.utf8)

    static func chart(_ symbol: String, price: Double, change: Double?, hint: Int = 2, close: Double? = nil) -> Data {
        let changed = change.map { #","regularMarketChangePercent":\#($0)"# } ?? ""
        let closed = close.map { #","chartPreviousClose":\#($0)"# } ?? ""
        return Data("""
            {"chart":{"result":[{"meta":{"currency":"USD","symbol":"\(symbol)","instrumentType":"EQUITY",
            "regularMarketPrice":\(price)\(changed)\(closed),"priceHint":\(hint)},"timestamp":[1795012200]}],
            "error":null}}
            """.utf8)
    }

    static let unknownSymbol = Data(
        #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#.utf8)

    static func event(_ id: String, _ title: String, from start: TimeInterval, for length: TimeInterval = 1800,
                      allDay: Bool = false) -> DayEvent {
        let begin = now.addingTimeInterval(start)
        return DayEvent(id: id, title: title, start: begin, end: begin.addingTimeInterval(length), isAllDay: allDay)
    }
}
