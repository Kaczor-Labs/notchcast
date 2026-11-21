// notchcast-addon-order: 150
// notchcast-readme: Capture: copy a color from anywhere on the screen
import SwiftUI

/// Pick any colour on screen with the system sampler; its value goes to the clipboard.
enum ColorPickerAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "colorPicker",
            title: String(localized: "Color Picker", table: "NotchcastColorPicker"),
            subtitle: String(localized: "Copy a color from anywhere on the screen.", table: "NotchcastColorPicker"),
            category: .capture
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "pick-color", name: String(localized: "Pick Color", table: "NotchcastColorPicker"),
            symbol: ColorPickerModule.symbol, switchID: ColorPickerModule.switchID,
            keywords: ["eyedropper", "hex", "rgb", "hsl", "sample"]
        ) { $0.module(ColorPickerModule.self)?.pick() },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: ColorPickerModule.switchID, searchTerms: [
            "color format",
            "recent picks",
        ]) { context in
            AnyView(ColorPickerSettingsView(defaults: context.defaults) {
                context.module(ColorPickerModule.self)?.copy($0)
            })
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ColorPickerModule(context: context, system: .live)
    }
}
