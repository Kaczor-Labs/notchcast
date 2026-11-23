import Foundation

extension DisplaySoundAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { brightnessID }

    struct Request: Codable {
        let value: Double
        let display: BrightnessDisplay.ID
    }

    static func settingsStatus(_ context: NotchcastContext) -> [BrightnessDisplay]? {
        context.settingsModule(DisplaySoundModule.self, for: settingsID)?.brightness.currentDisplays
    }

    static func answer(_ request: Request, context: NotchcastContext) async throws -> BrightnessLevel? {
        let brightness = context.settingsModule(DisplaySoundModule.self, for: settingsID)?.brightness
        return await brightness?.set(request.value, for: request.display)
    }
}
