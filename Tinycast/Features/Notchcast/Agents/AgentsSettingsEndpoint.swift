import Foundation

extension AgentsAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { AgentsPreferences.switchID }

    struct Status: Codable, Equatable, Sendable {
        let machineName: String?
        let accounts: [AgentsClaudeAccount]?
        let feedFolder: String?
    }

    enum Action: String, Codable {
        case refreshAgents
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        let settings = AgentsPreferences(defaults: context.defaults)
        return Status(machineName: settings.machineName, accounts: settings.claudeAccounts, feedFolder: settings.feedFolder)
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        context.settingsModule(AgentsModule.self, for: settingsID)?.settingsChanged()
    }
}
