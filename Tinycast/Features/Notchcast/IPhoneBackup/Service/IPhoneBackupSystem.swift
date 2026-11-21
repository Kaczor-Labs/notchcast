import Foundation

/// The system preference and the journal folder, injected so a harness touches neither; `.live` is in `+Live`.
struct IPhoneBackupSystem: Sendable {
    let read: @MainActor @Sendable () throws -> IPhoneBackupPolicy.Value?
    let write: @MainActor @Sendable (IPhoneBackupPolicy.Write) -> Bool
    let journalFolder: URL
    var readFile: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    var removeFile: @MainActor @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
}
