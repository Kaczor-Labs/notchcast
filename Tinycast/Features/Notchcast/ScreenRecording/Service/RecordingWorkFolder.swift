import Foundation
import Synchronization

/// Unfinished clips of one run: a folder of its own under `root`, held by a lock that ends with the process.
final class RecordingWorkFolder: Sendable {
    private let root: URL
    private let held = Mutex<(folder: URL, lock: Int32)?>(nil)

    init(root: URL) {
        self.root = root
    }

    /// This run's folder; a new one is claimed when the temporary directory was cleaned under it.
    func current() throws -> URL {
        try held.withLock { claim in
            if let claim, FileManager.default.fileExists(atPath: claim.folder.path(percentEncoded: false)) {
                return claim.folder
            }
            if let claim { close(claim.lock) }
            claim = nil
            let name = UUID().uuidString
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            // Locked under a hidden name first, so another copy never sees it unlocked.
            let hidden = root.appending(path: "." + name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
            let lock = Self.lock(hidden)
            guard lock >= 0 else {
                try? FileManager.default.removeItem(at: hidden)
                throw CocoaError(.fileLocking)
            }
            do {
                try FileManager.default.moveItem(at: hidden, to: folder)
            } catch {
                close(lock)
                try? FileManager.default.removeItem(at: hidden)
                throw error
            }
            claim = (folder, lock)
            return folder
        }
    }

    /// Folders of runs that ended: nothing holds their lock, so no running copy is still writing there.
    func abandoned() -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.filter {
            let lock = Self.lock($0)
            guard lock >= 0 else { return false }
            close(lock)
            return true
        }
    }

    /// The clips a capture wrote, each named by a UUID; a copied export lives there too and is not one.
    static func clips(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter {
            $0.pathExtension == "mov" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
        }
    }

    /// `rmdir` refuses a folder with anything in it, so a copied export keeps its folder.
    static func removeIfEmpty(_ folder: URL) {
        rmdir(folder.path(percentEncoded: false))
    }

    private static func lock(_ folder: URL) -> Int32 {
        open(folder.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_EXLOCK | O_NONBLOCK)
    }
}
