import Foundation

extension ColorPickerAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { ColorPickerModule.switchID }

    static func perform(_ color: ColorValuePayload, context: NotchcastContext) {
        context.settingsModule(ColorPickerModule.self, for: settingsID)?
            .copy(ColorValue(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
    }

    struct ColorValuePayload: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }
}
