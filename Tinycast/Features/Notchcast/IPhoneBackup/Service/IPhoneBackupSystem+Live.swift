import Foundation

extension IPhoneBackupSystem {
    static let live = preferences(
        domain: IPhoneBackupPolicy.domain,
        journalFolder: AppPaths.applicationSupport().appending(path: "Notchcast/IPhoneBackup", directoryHint: .isDirectory))
}
