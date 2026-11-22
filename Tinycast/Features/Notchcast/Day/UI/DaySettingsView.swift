import SwiftUI

/// Under the switch: the city the forecast is for and the symbols the markets list.
struct DaySettingsView: View {
    let context: NotchcastContext

    var body: some View {
        if let module = context.module(DayModule.self) {
            DaySettingsFields(module: module)
                .id(ObjectIdentifier(module))
        }
    }
}

private struct DaySettingsFields: View {
    let module: DayModule
    @State private var city: String
    @State private var symbols: String
    @State private var cityMissing = false
    @State private var isLooking = false

    init(module: DayModule) {
        self.module = module
        _city = State(initialValue: module.place?.name ?? "")
        _symbols = State(initialValue: module.symbolsText)
    }

    var body: some View {
        TextField(String(localized: "City", table: "NotchcastDay"), text: $city,
                  prompt: Text(verbatim: "Warsaw"))
            .onSubmit { lookUpCity() }
            .disabled(isLooking)
        if cityMissing {
            Text("No such city was found. Check the spelling and your connection.", tableName: "NotchcastDay")
                .foregroundStyle(Theme.Colors.destructive)
        }
        TextField(String(localized: "Symbols", table: "NotchcastDay"), text: $symbols,
                  prompt: Text(verbatim: "AAPL, BTC-USD, EURUSD=X"))
            .onSubmit {
                symbols = DayQuoteFeed.symbols(from: symbols).joined(separator: ", ")
                module.setSymbols(symbols)
            }
        Text("Press Return to apply. Weather comes from Open-Meteo. Quotes use Yahoo Finance symbols, up to 8.",
             tableName: "NotchcastDay")
            .foregroundStyle(Theme.Colors.textSecondary)
        Text("Events come from the Calendar feature and appear once it has calendar access.",
             tableName: "NotchcastDay")
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func lookUpCity() {
        isLooking = true
        Task {
            cityMissing = await !module.setCity(city)
            if let name = module.place?.name, !cityMissing { city = name }
            isLooking = false
        }
    }
}
