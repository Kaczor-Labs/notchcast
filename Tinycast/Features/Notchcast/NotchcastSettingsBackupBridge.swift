import Foundation
import Observation

/// The stock settings backup behind the core's hook: Backup › Export's file, settings only.
@MainActor
struct NotchcastSettingsBackupBridge: NotchcastSettingsBackup {
    weak var core: AppCore?

    func currentSettings() -> Data? {
        guard let core else { return nil }
        return try? SettingsBackup.gather(from: core).encoded()
    }

    func observeSettings(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        withObservationTracking {
            _ = currentSettings()
        } onChange: {
            // Fired before the new value lands, so read it on the next turn.
            Task { @MainActor in onChange() }
        }
    }

    func write(_ settings: Data, to file: URL) async throws {
        guard let core else { throw NotchcastNoSettingsBackup.Unavailable() }
        var plan = BackupComposer.plan([], from: core)
        plan.categories = [.configuration]
        plan.settings = settings
        try await Task.detached(priority: .utility) { [plan] in
            let staging = try BackupStaging()
            defer { staging.discard() }
            _ = try BackupComposer.write(plan, into: staging.bundle)
            let folder = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let partial = folder.appending(path: "." + file.lastPathComponent + ".partial")
            defer { try? FileManager.default.removeItem(at: partial) }
            try BackupArchive.seal(directory: staging.root, into: partial)
            // rename(2) replaces in one step, so a reader never sees half a backup.
            guard rename(partial.path(percentEncoded: false), file.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }.value
    }

    /// Backup › Import for a known file, so the stock confirmation and report come with it.
    func restore(_ file: URL) async {
        guard let core else { return }
        let symbol = "square.and.arrow.down"
        do {
            let (staging, manifest) = try await BackupActions.openBackup(at: file)
            defer { staging.discard() }
            guard let summary = await BackupActions.applyBackup(manifest.categories, from: staging, to: core)
            else { return }
            await core.showNotice(
                title: String(localized: "Backup Imported"), message: BackupActions.summaryText(summary),
                symbol: symbol, tone: .success)
        } catch {
            await core.showNotice(
                title: String(localized: "Import Failed"), message: error.localizedDescription, symbol: symbol,
                tone: .danger)
        }
    }
}
