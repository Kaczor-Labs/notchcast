import Foundation
import Observation

/// Applies and restores the backup preference through a journal file written before the system.
@MainActor
@Observable
final class IPhoneBackupStore {
    private(set) var isApplied = false
    private(set) var backupsOff = false
    @ObservationIgnored private let context: NotchcastContext
    @ObservationIgnored private let system: IPhoneBackupSystem

    private struct WriteFailed: Error {}
    private struct JournalNotSaved: Error {}
    private struct JournalCorrupt: Error {}

    init(context: NotchcastContext, system: IPhoneBackupSystem) {
        self.context = context
        self.system = system
    }

    func refresh() {
        isApplied = (try? loadJournal()).map(IPhoneBackupPolicy.isApplied) ?? false
        backupsOff = (try? system.read()) == IPhoneBackupPolicy.disabled
    }

    /// Saves the previous value before writing; a failed capture turns the switch back off.
    func apply() {
        guard context.isEnabled(IPhoneBackupAddon.switchID) else { return }
        defer { refresh() }
        guard let journal = try? loadJournal() else {
            // An unreadable journal may hold a real capture, so the switch stays on to keep it restorable.
            report(Self.turnOffFailedText)
            return
        }
        let write: IPhoneBackupPolicy.Write
        do {
            let plan = IPhoneBackupPolicy.apply(current: try system.read(), journal: journal)
            try save(plan.journal)
            write = plan.write
        } catch {
            // The journal may be unverified, so the teardown this switch-off causes must not restore from it.
            context.defaults.set(true, forKey: IPhoneBackupPolicy.skipRestoreKey)
            turnOffFailed()
            return
        }
        guard !system.write(write) else { return }
        // A failed sync can still leave the value written, so the capture rolls it back.
        if restore() { turnOffFailed() }
    }

    func decline() {
        context.preferences.set(IPhoneBackupAddon.switchID, on: false)
    }

    /// A failed write keeps the switch on and the capture saved, so switching off retries.
    /// A corrupt journal is kept and reported once; the switch stays off and restores are skipped.
    @discardableResult
    func restore() -> Bool {
        defer { refresh() }
        guard !context.defaults.bool(forKey: IPhoneBackupPolicy.skipRestoreKey) else { return true }
        do {
            try restoreJournal()
            return true
        } catch is JournalCorrupt {
            context.defaults.set(true, forKey: IPhoneBackupPolicy.skipRestoreKey)
            report(String(localized: "Couldn’t restore iPhone auto backups", table: "NotchcastIPhoneBackup"))
            return false
        } catch {
            context.preferences.set(IPhoneBackupAddon.switchID, on: true)
            report(String(localized: "Couldn’t restore iPhone auto backups", table: "NotchcastIPhoneBackup"))
            return false
        }
    }

    private func restoreJournal() throws {
        guard let write = IPhoneBackupPolicy.restore(journal: try loadJournal()) else { return }
        guard system.write(write) else { throw WriteFailed() }
        if FileManager.default.fileExists(atPath: journalFile.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: journalFile)
        }
        context.defaults.removeObject(forKey: IPhoneBackupPolicy.journalKey)
    }

    private func turnOffFailed() {
        context.preferences.set(IPhoneBackupAddon.switchID, on: false)
        report(Self.turnOffFailedText)
    }

    private static var turnOffFailedText: String {
        String(localized: "Couldn’t turn off iPhone auto backups", table: "NotchcastIPhoneBackup")
    }

    private var journalFile: URL { system.journalFolder.appending(path: IPhoneBackupPolicy.journalFile) }

    /// Absent is empty; anything present that is not a readable journal, whatever its type, is corrupt.
    private func loadJournal() throws -> IPhoneBackupPolicy.Journal {
        do {
            if FileManager.default.fileExists(atPath: journalFile.path(percentEncoded: false)) {
                return try IPhoneBackupPolicy.journal(from: system.readFile(journalFile))
            }
            let v1 = context.defaults.object(forKey: IPhoneBackupPolicy.journalKey)
            guard v1 == nil || v1 is Data else { throw JournalCorrupt() }
            return try IPhoneBackupPolicy.journal(from: v1 as? Data)
        } catch {
            throw JournalCorrupt()
        }
    }

    /// Read back before returning, so the system is written only once the capture is on disk.
    private func save(_ journal: IPhoneBackupPolicy.Journal) throws {
        try FileManager.default.createDirectory(at: system.journalFolder, withIntermediateDirectories: true)
        try IPhoneBackupPolicy.data(journal).write(to: journalFile, options: .atomic)
        guard try IPhoneBackupPolicy.journal(from: system.readFile(journalFile)) == journal else {
            throw JournalNotSaved()
        }
        context.defaults.removeObject(forKey: IPhoneBackupPolicy.skipRestoreKey)
    }

    private func report(_ text: String) {
        context.presenter.post(
            IslandNotice(id: IPhoneBackupAddon.switchID, symbol: "iphone", text: text, isFailure: true), onTap: nil)
    }
}
