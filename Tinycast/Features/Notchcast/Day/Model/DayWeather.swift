import Foundation

/// The place the forecast is for, as the user's city resolved.
struct DayPlace: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// One moment of weather: degrees Celsius and a WMO weather code.
struct DayWeatherHour: Equatable, Sendable {
    var at: Date
    var celsius: Double
    var code: Int
    var isDay: Bool
}

struct DayWeather: Equatable, Sendable {
    var current: DayWeatherHour
    /// Whole hours after `current`, oldest first.
    var hours: [DayWeatherHour]
}

/// Open-Meteo's forecast and city search: the requests and what their answers mean.
enum DayWeatherFeed {
    /// The page shows this many coming hours.
    static let hourCount = 5
    static let nameLimit = 80

    static func forecastURL(_ place: DayPlace) -> URL? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_hours", value: String(hourCount + 2)),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return parts?.url
    }

    static func searchURL(_ city: String) -> URL? {
        let name = String(city.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        guard !name.isEmpty else { return nil }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        parts?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return parts?.url
    }

    private struct Forecast: Decodable {
        enum Key: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case code = "weather_code"
            case isDay = "is_day"
        }
        struct Current: Decodable {
            let time: Double
            let temperature: Double
            let code: Int
            let isDay: Int

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: Key.self)
                time = try values.decode(Double.self, forKey: .time)
                temperature = try values.decode(Double.self, forKey: .temperature)
                code = try values.decode(Int.self, forKey: .code)
                isDay = try values.decode(Int.self, forKey: .isDay)
            }
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature: [Double]
            let code: [Int]
            let isDay: [Int]

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: Key.self)
                time = try values.decode([Double].self, forKey: .time)
                temperature = try values.decode([Double].self, forKey: .temperature)
                code = try values.decode([Int].self, forKey: .code)
                isDay = try values.decode([Int].self, forKey: .isDay)
            }
        }
        let current: Current
        let hourly: Hourly
    }

    private struct Search: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }
        let results: [Result]?
    }

    /// Nil unless the whole answer is sound; the hours kept are those after the current reading.
    static func weather(from data: Data) -> DayWeather? {
        guard let forecast = try? JSONDecoder().decode(Forecast.self, from: data) else { return nil }
        let hourly = forecast.hourly
        let count = hourly.time.count
        guard hourly.temperature.count == count, hourly.code.count == count, hourly.isDay.count == count,
              let current = hour(forecast.current.time, forecast.current.temperature, forecast.current.code,
                                 forecast.current.isDay) else { return nil }
        let hours = (0..<count).compactMap {
            hour(hourly.time[$0], hourly.temperature[$0], hourly.code[$0], hourly.isDay[$0])
        }
        guard hours.count == count else { return nil }
        return DayWeather(current: current,
                          hours: Array(hours.filter { $0.at > current.at }.sorted { $0.at < $1.at }.prefix(hourCount)))
    }

    private static func hour(_ time: Double, _ celsius: Double, _ code: Int, _ isDay: Int) -> DayWeatherHour? {
        guard time.isFinite, time > 0, celsius.isFinite, (-100...100).contains(celsius) else { return nil }
        return DayWeatherHour(at: Date(timeIntervalSince1970: time), celsius: celsius, code: code, isDay: isDay != 0)
    }

    /// The first match, with its name cut to length and its coordinates on the globe.
    static func place(from data: Data) -> DayPlace? {
        guard let result = (try? JSONDecoder().decode(Search.self, from: data))?.results?.first,
              (-90...90).contains(result.latitude), (-180...180).contains(result.longitude) else { return nil }
        let name = String(result.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return name.isEmpty ? nil : DayPlace(name: name, latitude: result.latitude, longitude: result.longitude)
    }

    /// WMO weather interpretation codes, as Open-Meteo documents them.
    enum Condition: Equatable, Sendable {
        case clear, mostlyClear, partlyCloudy, cloudy, fog, drizzle, rain, freezingRain, snow, showers, thunderstorm
        case unknown

        init(code: Int) {
            self = switch code {
            case 0: .clear
            case 1: .mostlyClear
            case 2: .partlyCloudy
            case 3: .cloudy
            case 45, 48: .fog
            case 51, 53, 55: .drizzle
            case 61, 63, 65: .rain
            case 56, 57, 66, 67: .freezingRain
            case 71, 73, 75, 77, 85, 86: .snow
            case 80, 81, 82: .showers
            case 95, 96, 99: .thunderstorm
            default: .unknown
            }
        }
    }

    static func symbol(_ hour: DayWeatherHour) -> String {
        switch Condition(code: hour.code) {
        case .clear: hour.isDay ? "sun.max" : "moon.stars"
        case .mostlyClear, .partlyCloudy: hour.isDay ? "cloud.sun" : "cloud.moon"
        case .cloudy: "cloud"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain: "cloud.rain"
        case .freezingRain: "cloud.sleet"
        case .snow: "cloud.snow"
        case .showers: "cloud.heavyrain"
        case .thunderstorm: "cloud.bolt.rain"
        case .unknown: "thermometer.medium"
        }
    }

    static func words(_ hour: DayWeatherHour) -> String {
        switch Condition(code: hour.code) {
        case .clear: String(localized: "Clear", table: "NotchcastDay")
        case .mostlyClear: String(localized: "Mostly Clear", table: "NotchcastDay")
        case .partlyCloudy: String(localized: "Partly Cloudy", table: "NotchcastDay")
        case .cloudy: String(localized: "Cloudy", table: "NotchcastDay")
        case .fog: String(localized: "Fog", table: "NotchcastDay")
        case .drizzle: String(localized: "Drizzle", table: "NotchcastDay")
        case .rain: String(localized: "Rain", table: "NotchcastDay")
        case .freezingRain: String(localized: "Freezing Rain", table: "NotchcastDay")
        case .snow: String(localized: "Snow", table: "NotchcastDay")
        case .showers: String(localized: "Showers", table: "NotchcastDay")
        case .thunderstorm: String(localized: "Thunderstorm", table: "NotchcastDay")
        case .unknown: String(localized: "Weather", table: "NotchcastDay")
        }
    }

    /// Whole degrees in the locale's own scale, with no unit letter: "9°".
    static func degrees(_ celsius: Double, locale: Locale) -> String {
        let value = locale.measurementSystem == .us ? celsius * 9 / 5 + 32 : celsius
        return Int(value.rounded()).formatted(.number.locale(locale)) + "°"
    }
}
