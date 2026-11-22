import Foundation

extension ScriptCommandsAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switchID }

    struct Status: Codable, Equatable, Sendable {
        let rows: [ScriptCommand]
        let running: [String]
        let outputRevisions: [String: Int]
    }

    enum Action: Codable {
        case addScript(String)
        case updateScript(ScriptCommand)
        case deleteScript(String)
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        guard let scripts = context.settingsModule(ScriptCommandsModule.self, for: settingsID) else { return nil }
        return Status(rows: scripts.rows, running: scripts.running.sorted(), outputRevisions: scripts.outputRevisions)
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        guard let scripts = context.settingsModule(ScriptCommandsModule.self, for: settingsID) else { return }
        switch action {
        case .addScript(let id): scripts.addRow(id: id)
        case .updateScript(let row): scripts.update(row)
        case .deleteScript(let id): scripts.removeRow(id)
        }
    }

    static func answer(_ id: String, context: NotchcastContext) async throws -> String? {
        context.settingsModule(ScriptCommandsModule.self, for: settingsID)?.outputs[id]
    }
}
