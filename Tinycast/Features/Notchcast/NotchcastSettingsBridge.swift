import Foundation

extension AppCore {
    func notchcastSettingsStatus() -> NotchcastSettingsStatus {
        var status = NotchcastSettingsStatus()
        for slot in notchcast?.controller.slots ?? [] {
            guard let endpoint = slot.addon as? any NotchcastSettingsEndpoint.Type else { continue }
            status.addons[endpoint.settingsID] = endpoint.encodedStatus(slot.context)
        }
        status.dictationCleanupModel = dictationExtras.cleanupModel
        status.dictationAutomaticModelTitle = dictationExtras.automaticModel?.title
        status.hasDictationHistory = !dictationExtras.history.entries.isEmpty
        status.dictationModelSizes = notchcast?.dictationModelSizes?.sizes ?? [:]
        return status
    }

    func performNotchcastSettingsAction(_ action: NotchcastSettingsAction) {
        switch action {
        case .addon(let message):
            guard let (endpoint, context) = settingsEndpoint(message.id) else { return }
            endpoint.performSettingsAction(message.payload, context: context)
        case .selectDictationCleanupModel(let selection):
            dictationExtras.selectCleanupModel(selection)
        case .restoreAutomaticBackup(let file):
            Task { await NotchcastSettingsBackupBridge(core: self).restore(file) }
        }
    }

    func performNotchcastSettingsCall(_ call: NotchcastSettingsMessage) async throws -> Data {
        guard let (endpoint, context) = settingsEndpoint(call.id) else { throw CancellationError() }
        return try await endpoint.answerSettingsRequest(call.payload, context: context)
    }

    private func settingsEndpoint(_ id: String) -> (any NotchcastSettingsEndpoint.Type, NotchcastContext)? {
        for slot in notchcast?.controller.slots ?? [] {
            if let endpoint = slot.addon as? any NotchcastSettingsEndpoint.Type, endpoint.settingsID == id {
                return (endpoint, slot.context)
            }
        }
        return nil
    }
}

extension NotchcastContext {
    func settingsModule<Module: NotchcastModule>(_ type: Module.Type, for id: String) -> Module? {
        guard isEnabled(id) else { return nil }
        return module(type)
    }
}
