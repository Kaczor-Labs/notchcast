import Foundation

protocol CleanerFileSystem: Sendable {
    func inspect(_ url: URL) throws -> CleanerFile
    func children(of folder: URL, limit: Int) throws -> [String]
    func openFiles() throws -> Set<CleanerFile.Identity>
    func trash(_ url: URL) throws
}

enum CleanerFileError: Error {
    case missing
    case unreadable
}

struct CleanerFile: Equatable, Sendable {
    struct Identity: Hashable, Sendable {
        let device: Int32
        let inode: UInt64
        let birthSeconds: Int64
        let birthNanoseconds: Int
    }

    let identity: Identity
    let facts: PathFacts
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int
    let changedSeconds: Int64
    let changedNanoseconds: Int
    let isRegularFile: Bool

    var modified: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000)
    }
}
