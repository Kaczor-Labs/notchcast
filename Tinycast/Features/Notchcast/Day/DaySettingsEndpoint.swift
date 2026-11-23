import Foundation

extension DayAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switches[0].id }

    static func settingsStatus(_ context: NotchcastContext) -> String? {
        context.defaults.string(forKey: DayModule.symbolsKey) ?? ""
    }

    static func perform(_ text: String, context: NotchcastContext) {
        context.settingsModule(DayModule.self, for: settingsID)?.setSymbols(text)
    }

    static func answer(_ city: String, context: NotchcastContext) async throws -> String? {
        guard let day = context.settingsModule(DayModule.self, for: settingsID) else { throw CancellationError() }
        guard await day.setCity(city) else { return nil }
        return day.place?.name ?? ""
    }
}
