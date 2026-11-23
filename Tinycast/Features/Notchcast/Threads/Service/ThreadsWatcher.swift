import Darwin
import Foundation

/// Hears the waits file change, by rename or in place; no timer, so a missing folder waits for the next ask.
@MainActor
final class ThreadsWatcher {
    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    isolated deinit { cancel() }

    var isWatching: Bool { folderSource != nil }

    /// The file is reopened every time: a save by rename leaves the old descriptor on a dead inode.
    func arm() {
        if folderSource == nil {
            folderSource = source(watching: fileURL.deletingLastPathComponent(), events: [.write, .delete, .rename, .revoke])
        }
        fileSource?.cancel()
        fileSource = source(watching: fileURL, events: [.write, .extend, .delete, .rename, .revoke])
    }

    func cancel() {
        folderSource?.cancel()
        folderSource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    private func source(watching url: URL, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.fired() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }

    private func fired() {
        if !FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) {
            folderSource?.cancel()
            folderSource = nil
        }
        arm()
        onChange()
    }
}
