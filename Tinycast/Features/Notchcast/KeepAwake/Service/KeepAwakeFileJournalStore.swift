import Darwin
import Foundation

/// The sleep journal as one fsynced file per channel, so it outlives a crash or power loss.
@MainActor
final class KeepAwakeFileJournalStore: KeepAwakeJournalStore {
    enum Failure: Error {
        case posix(String, Int32)
        case outsideRoot
    }

    let url: URL
    private let root: String
    private let syncFolder: (String) throws -> Void
    /// Set once every folder between the journal and `root` is fsynced into its parent.
    private var established = false

    /// `root` must already be durable; each folder below it is fsynced into its parent before use.
    init(url: URL, root: URL, syncFolder: @escaping (String) throws -> Void = fsyncFolder) {
        self.url = url
        self.root = root.standardizedFileURL.path
        self.syncFolder = syncFolder
    }

    func load() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ data: Data?) throws {
        let folder = url.deletingLastPathComponent()
        try establish(folder.standardizedFileURL.path)
        if let data {
            let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
            defer { unlink(temporary.path) }
            try Self.writeSynced(data, to: temporary.path)
            try Self.check(rename(temporary.path, url.path), "rename")
        } else if unlink(url.path) != 0, errno != ENOENT {
            throw Failure.posix("unlink", errno)
        }
        try syncFolder(folder.path)
    }

    /// A new folder's entry lives in its parent, so until each parent is fsynced a crash can lose it.
    private func establish(_ folder: String) throws {
        var chain = [folder]
        while let last = chain.last, last != root {
            let parent = (last as NSString).deletingLastPathComponent
            guard parent != last else { throw Failure.outsideRoot }
            chain.append(parent)
        }
        var created = false
        for directory in chain.dropLast().reversed() {
            if mkdir(directory, 0o700) == 0 {
                created = true
            } else if errno != EEXIST {
                throw Failure.posix("mkdir", errno)
            }
        }
        guard created || !established else { return }
        established = false
        for parent in chain.dropFirst() { try syncFolder(parent) }
        established = true
    }

    private static func writeSynced(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        try check(descriptor, "open")
        defer { close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                try check(written < 0 ? -1 : 0, "write")
                offset += written
            }
        }
        try fullSync(descriptor)
    }

    nonisolated static func fsyncFolder(_ path: String) throws {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        try check(descriptor, "open")
        defer { close(descriptor) }
        try fullSync(descriptor)
    }

    /// `fsync` alone leaves the bytes in the drive's cache; a volume without F_FULLFSYNC falls back.
    private nonisolated static func fullSync(_ descriptor: Int32) throws {
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        try check(fsync(descriptor), "fsync")
    }

    private nonisolated static func check(_ result: Int32, _ call: String) throws {
        if result < 0 { throw Failure.posix(call, errno) }
    }
}
