import Foundation
import Synchronization

final class CleanerTestFileSystem: CleanerFileSystem {
    private struct State {
        var files: [String: CleanerFile] = [:]
        var links: [String: String] = [:]
        var trashCalls: [URL] = []
        var openFiles = CleanerOpenFiles()
        var refused: Set<String> = []
        var swapped: Set<String> = []
        var lost: Set<String> = []
        var reads = 0
        var nextInode: UInt64 = 0
    }

    private let state = Mutex(State())
    private let beforeInspect: @Sendable (URL) -> Void
    static let area = CleanerArea(home: URL(fileURLWithPath: "/Users/example", isDirectory: true))
    static let now = Date(timeIntervalSince1970: 10_000)

    init(beforeInspect: @escaping @Sendable (URL) -> Void = { _ in }) {
        self.beforeInspect = beforeInspect
        for path in ["/", "/Users", Self.area.home.path, Self.area.home.path + "/Library", Self.area.root.path] {
            put(URL(filePath: path, directoryHint: .notDirectory), directory: true)
        }
    }

    var scanner: CleanerScanner {
        let start = ContinuousClock.now
        return CleanerScanner(fileSystem: self, clock: { Self.now }, monotonic: { start })
    }

    var trashCalls: [URL] { state.withLock { $0.trashCalls } }
    var reads: Int { state.withLock { $0.reads } }

    static func item(_ name: String) -> URL { area.root.appending(path: name) }

    func put(
        _ url: URL, directory: Bool = false, size: Int64 = 0, modified: Int64 = 1_000,
        locked: Bool = false, link: Bool = false
    ) {
        state.withLock { state in
            state.nextInode += 1
            state.files[url.path] = CleanerFile(
                identity: .init(device: 1, inode: state.nextInode, birthSeconds: 123, birthNanoseconds: 0),
                facts: PathFacts(path: url.path, isSymbolicLink: link, isUserImmutable: locked, isDirectory: directory),
                size: size, modifiedSeconds: modified, modifiedNanoseconds: 0, changedSeconds: modified,
                changedNanoseconds: 0, isRegularFile: !directory && !link)
        }
    }

    func putLink(_ url: URL, destination: String) {
        put(url, link: true)
        state.withLock { $0.links[url.path] = destination }
    }

    func linkDestination(of url: URL) throws -> String {
        try state.withLock {
            guard let destination = $0.links[url.path] else { throw CleanerFileError.unreadable }
            return destination
        }
    }

    func remove(_ url: URL) {
        state.withLock { $0.files[url.path] = nil }
    }

    func failTrash(of url: URL) {
        _ = state.withLock { $0.refused.insert(url.path) }
    }

    func holdOpen(_ url: URL) throws {
        let identity = try inspect(url).identity
        _ = state.withLock { $0.openFiles.held.insert(identity) }
    }

    func run(_ url: URL) throws {
        let identity = try inspect(url).identity
        _ = state.withLock { $0.openFiles.running.insert(identity) }
    }

    func runScript(named path: String) {
        _ = state.withLock { $0.openFiles.runningPaths.insert(path) }
    }

    func swapDuringTrash(of url: URL) {
        _ = state.withLock { $0.swapped.insert(url.path) }
    }

    func loseInTrash(_ url: URL) {
        _ = state.withLock { $0.lost.insert(url.path) }
    }

    static let trash = area.home.appending(path: ".Trash")

    func inspect(_ url: URL) throws -> CleanerFile {
        beforeInspect(url)
        return try state.withLock {
            $0.reads += 1
            guard let file = $0.files[url.path] else { throw CleanerFileError.missing }
            return file
        }
    }

    func children(of folder: URL, limit: Int) throws -> [String] {
        try state.withLock {
            $0.reads += 1
            let names = $0.files.keys.compactMap { path -> String? in
                let url = URL(filePath: path, directoryHint: .notDirectory)
                return url.deletingLastPathComponent().path == folder.path ? url.lastPathComponent : nil
            }
            guard names.count <= limit else { throw CleanerHoldBack.scanLimit }
            return names
        }
    }

    func openFiles() throws -> CleanerOpenFiles {
        state.withLock { $0.openFiles }
    }

    func trash(_ url: URL) throws -> URL? {
        let destination = Self.trash.appending(component: url.lastPathComponent)
        if state.withLock({ $0.swapped.contains(url.path) }) { put(url) }
        return try state.withLock {
            $0.trashCalls.append(url)
            if $0.refused.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
            for (path, file) in $0.files where path == url.path || path.hasPrefix(url.path + "/") {
                $0.files[path] = nil
                if !$0.lost.contains(url.path) { $0.files[destination.path + path.dropFirst(url.path.count)] = file }
            }
            return destination
        }
    }
}
