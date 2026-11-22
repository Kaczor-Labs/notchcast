import Foundation

extension LowDiskAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switches[0].id }

    enum Action: String, Codable {
        case checkLowDisk
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        context.settingsModule(LowDiskModule.self, for: settingsID)?.check()
    }
}
