import SwiftUI

/// Under the switch: the city the forecast is for and the symbols the markets list.
struct DaySettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    let context: NotchcastContext
    @State private var city = ""
    @State private var symbols = ""
    @State private var cityMissing = false
    @State private var isLooking = false

    var body: some View {
        Group {
            TextField(String(localized: "City", table: "NotchcastDay"), text: $city,
                      prompt: Text(verbatim: "Warsaw"))
                .onSubmit { isLooking = true }
                .disabled(isLooking)
            if cityMissing {
                Text("No such city was found. Check the spelling and your connection.", tableName: "NotchcastDay")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            TextField(String(localized: "Symbols", table: "NotchcastDay"), text: $symbols,
                      prompt: Text(verbatim: "AAPL, BTC-USD, EURUSD=X"))
                .onSubmit {
                    symbols = DayQuoteFeed.symbols(from: symbols).joined(separator: ", ")
                    mainApp.sendNotchcast(.setSymbols(symbols), to: DayAddon.self)
                }
            Text("Press Return to apply. Weather comes from Open-Meteo. Quotes use Yahoo Finance symbols, up to 8.",
                 tableName: "NotchcastDay")
                .foregroundStyle(Theme.Colors.textSecondary)
            if mainApp.notchcastStatus(for: DayAddon.self)?.needsCalendarAccess == true {
                LabeledContent {
                    Button {
                        mainApp.sendNotchcast(.requestCalendarAccess, to: DayAddon.self)
                    } label: {
                        Text("Grant Access…", tableName: "NotchcastDay")
                    }
                } label: {
                    Text("Calendar access is needed", tableName: "NotchcastDay")
                }
            }
        }
        .onAppear {
            city = context.defaults.data(forKey: DayModule.placeKey)
                .flatMap { try? JSONDecoder().decode(DayPlace.self, from: $0) }?.name ?? ""
        }
        .onChange(of: mainApp.notchcastStatus(for: DayAddon.self)?.symbols, initial: true) { _, latest in
            if let latest { symbols = latest }
        }
        .task(id: isLooking) {
            guard isLooking else { return }
            defer { if !Task.isCancelled { isLooking = false } }
            do {
                let name = try await mainApp.callNotchcast(city, to: DayAddon.self)
                guard !Task.isCancelled else { return }
                if let name {
                    city = name
                    cityMissing = false
                } else {
                    cityMissing = true
                }
            } catch {
                if !Task.isCancelled { cityMissing = true }
            }
        }
    }
}
