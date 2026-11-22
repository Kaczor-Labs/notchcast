import Foundation

extension IPhoneBackupAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switchID }

    struct Status: Codable, Equatable, Sendable {
        let isApplied: Bool
        let backupsOff: Bool
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        guard let iPhone = context.settingsModule(IPhoneBackupModule.self, for: settingsID) else { return nil }
        let status = iPhone.settingsStatus()
        return Status(isApplied: status.isApplied, backupsOff: status.backupsOff)
    }

    static func perform(_ accepted: Bool, context: NotchcastContext) {
        context.settingsModule(IPhoneBackupModule.self, for: settingsID)?.answer(accepted)
    }
}
