import Foundation

extension ArchivesAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { ArchivesModule.switchID }

    static func perform(_ enabled: Bool, context: NotchcastContext) {
        context.settingsModule(ArchivesModule.self, for: settingsID)?.setDefaultApp(enabled)
    }
}
