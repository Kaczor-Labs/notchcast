import SwiftUI

/// Under the switch: the city the forecast is for and the symbols the markets list.
struct DaySettingsView: View {
    let context: NotchcastContext
    @State private var module: DayModule?
    @State private var city = ""
    @State private var symbols = ""
    @State private var cityMissing = false
    @State private var isLooking = false

    var body: some View {
        Group {
            if let module {
                TextField(String(localized: "City", table: "NotchcastDay"), text: $city,
                          prompt: Text(verbatim: "Warsaw"))
                    .onSubmit { lookUp(module) }
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
        }
        .task { await attach() }
    }

    /// The core attaches the module a moment after the switch turns on, so wait for it briefly.
    private func attach() async {
        for _ in 0..<40 {
            if let found = context.module(DayModule.self) {
                city = found.place?.name ?? ""
                symbols = found.symbolsText
                module = found
                return
            }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
    }

    private func lookUp(_ module: DayModule) {
        isLooking = true
        Task {
            cityMissing = await !module.setCity(city)
            if let name = module.place?.name, !cityMissing { city = name }
            isLooking = false
        }
    }
}
