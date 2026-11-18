import Foundation

/// Every fact the module takes from the Mac; a harness passes its own files, clock and wake-ups.
struct AgentsSystem {
    typealias Cancel = @MainActor () -> Void

    var folder: URL
    /// Makes the feed folder, the one thing Notchcast ever writes there.
    var prepare: @MainActor () -> Void
    var read: @MainActor (_ fileName: String) -> AgentsFeedFile
    var watch: @MainActor (_ onChange: @escaping @MainActor () -> Void) -> Cancel
    var wake: @MainActor (_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancel
    var open: @MainActor (URL) -> Void
    var region: @MainActor () -> AgentsRegion
}

/// Reads one feed file and nothing it points at: a link could name another app's file (946-5).
enum AgentsFeedReader {
    static func file(at url: URL) -> AgentsFeedFile {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard let values, values.isRegularFile == true, values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: url) else { return .missing }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: AgentsFeedFile.maxBytes + 1)) ?? Data()
        return data.count > AgentsFeedFile.maxBytes ? .tooLarge : .data(data)
    }
}

/// Watches the feed folder's own entries: a file renamed into it is one event, so nothing polls.
@MainActor
final class AgentsFolderWatcher {
    private let folder: URL
    private let onChange: @MainActor () -> Void
    private var source: (any DispatchSourceFileSystemObject)?

    init(folder: URL, onChange: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    func start() {
        stop()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// A folder deleted or moved away keeps its old descriptor, so it is made and watched again.
    private func changed() {
        guard source != nil else { return }
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            start()
        }
        onChange()
    }

    isolated deinit { source?.cancel() }
}
