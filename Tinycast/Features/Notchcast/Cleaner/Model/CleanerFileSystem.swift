// The running-program hold is adapted from Dragos Tugui's Peel, OpenFiles.swift @ 20230794 (GPL-3.0).
import Foundation

protocol CleanerFileSystem: Sendable {
    func inspect(_ url: URL) throws -> CleanerFile
    func children(of folder: URL, limit: Int) throws -> [String]
    func linkDestination(of url: URL) throws -> String
    func openFiles() throws -> CleanerOpenFiles
    func trash(_ url: URL) throws -> URL?
}

struct CleanerOpenFiles: Equatable, Sendable {
    var held: Set<CleanerFile.Identity> = []
    var running: Set<CleanerFile.Identity> = []
    var runningPaths: Set<String> = []

    func hold(on snapshot: CleanerSnapshot, row: URL, checkingHeld: Bool = true) -> CleanerHoldBack? {
        let identities = snapshot.entries.values.map(\.identity)
        if identities.contains(where: running.contains) || runsInside(row) { return .runningProgram }
        return checkingHeld && identities.contains(where: held.contains) ? .openFile : nil
    }

    // A script named through a link runs from the link's folder, so its path counts as named.
    private func runsInside(_ row: URL) -> Bool {
        let root = Self.folded(row.standardizedFileURL.path)
        return runningPaths.contains {
            let path = Self.folded($0)
            return path == root || path.hasPrefix(root + "/")
        }
    }

    private static func folded(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
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
