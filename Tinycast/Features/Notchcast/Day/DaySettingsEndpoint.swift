import Foundation

extension DayAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switches[0].id }

    struct Status: Codable, Equatable, Sendable {
        var symbols: String
        var needsCalendarAccess: Bool
    }

    enum Action: Codable, Sendable {
        case setSymbols(String)
        case requestCalendarAccess
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        Status(symbols: context.defaults.string(forKey: DayModule.symbolsKey) ?? "",
               needsCalendarAccess: context.calendar.needsAccess())
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        switch action {
        case .setSymbols(let text):
            context.settingsModule(DayModule.self, for: settingsID)?.setSymbols(text)
        case .requestCalendarAccess:
            guard context.isEnabled(settingsID) else { return }
            Task { await context.calendar.requestAccess(true) }
        }
    }

    static func answer(_ city: String, context: NotchcastContext) async throws -> String? {
        guard let day = context.settingsModule(DayModule.self, for: settingsID) else { throw CancellationError() }
        guard await day.setCity(city) else { return nil }
        return day.place?.name ?? ""
    }
}
