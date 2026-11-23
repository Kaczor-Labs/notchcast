import Foundation

extension ThreadsAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { ThreadsPreferences.switchID }

    struct Status: Codable, Equatable, Sendable {
        let waitsFile: String?
    }

    enum Action: String, Codable {
        case reloadThreads
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        Status(waitsFile: ThreadsPreferences(defaults: context.defaults).waitsFile)
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        context.settingsModule(ThreadsModule.self, for: settingsID)?.settingsChanged()
    }
}
