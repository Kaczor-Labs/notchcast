import Foundation

@MainActor
final class IPhoneBackupModule: NotchcastModule {
    private let context: NotchcastContext
    private let store: IPhoneBackupStore
    private var hasReadSettingsStatus = false

    init(context: NotchcastContext, system: IPhoneBackupSystem) {
        self.context = context
        store = IPhoneBackupStore(context: context, system: system)
    }

    func start() {}

    func settingsStatus() -> (isApplied: Bool, backupsOff: Bool) {
        if !hasReadSettingsStatus {
            hasReadSettingsStatus = true
            store.refresh()
        }
        return (store.isApplied, store.backupsOff)
    }

    func answer(_ accepted: Bool) {
        if accepted { store.apply() } else { store.decline() }
    }

    /// Quitting stops the module with the switch still on, and must leave backups off.
    func stop() {
        guard !context.isEnabled(IPhoneBackupAddon.switchID) else { return }
        store.restore()
    }
}
