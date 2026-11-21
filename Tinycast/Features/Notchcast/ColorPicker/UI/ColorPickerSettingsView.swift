import SwiftUI

struct ColorPickerSettingsView: View {
    @AppStorage private var format: ColorPickerFormat
    @AppStorage private var recent: String
    @Environment(MainAppLink.self) private var mainApp
    private static let anchor = NotchcastSettingsSearch.anchor(.capture)

    init(defaults: UserDefaults) {
        _format = AppStorage(wrappedValue: .hex, ColorPickerFormat.defaultsKey, store: defaults)
        _recent = AppStorage(wrappedValue: "", ColorPickerHistory.defaultsKey, store: defaults)
    }

    var body: some View {
        Picker(selection: $format) {
            Text(verbatim: "#RRGGBB").tag(ColorPickerFormat.hex)
            Text(verbatim: "rgb()").tag(ColorPickerFormat.rgb)
            Text(verbatim: "hsl()").tag(ColorPickerFormat.hsl)
            Text(verbatim: "SwiftUI Color()").tag(ColorPickerFormat.swiftUI)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Color format", table: "NotchcastColorPicker"))
            Text("How a picked color is copied.", tableName: "NotchcastColorPicker")
        }
        let colors = ColorPickerHistory.colors(recent)
        if !colors.isEmpty {
            LabeledContent {
                EmptyView()
            } label: {
                SettingsRowTitle(Self.anchor, LocalizedStringResource("Recent picks", table: "NotchcastColorPicker"))
                Text("Copy one again in the chosen format.", tableName: "NotchcastColorPicker")
            }
        }
        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
            let value = format.string(for: color)
            LabeledContent {
                Button {
                    mainApp.send(.notchcast(.copyColor(
                        red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)))
                } label: {
                    Text("Copy", tableName: "NotchcastColorPicker")
                }
                .accessibilityLabel(Text("Copy \(value)", tableName: "NotchcastColorPicker"))
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    ColorSwatch(color: color)
                        .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    Text(verbatim: value)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
