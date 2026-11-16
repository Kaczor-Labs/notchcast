import Foundation

@MainActor
final class IPhoneBackupModule: NotchcastModule {
    private let context: NotchcastContext
    private let store: IPhoneBackupStore

    init(context: NotchcastContext, system: IPhoneBackupSystem) {
        self.context = context
        store = IPhoneBackupStore(context: context, system: system)
    }

    func start() {}

    /// Quitting stops the module with the switch still on, and must leave backups off.
    func stop() {
        guard !context.isEnabled(IPhoneBackupAddon.switchID) else { return }
        store.restore()
    }
}
