import CoreGraphics
import CoreServices
import Foundation

extension LowDiskModule {
    /// The startup volume's space for important usage, which counts purgeable space as free.
    @concurrent
    static func readStartupDisk() async throws -> Int64 {
        let values = try URL(filePath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage else { throw CocoaError(.fileReadUnknown) }
        return free
    }

    static func isMainDisplayAsleep() -> Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }

    static func watchStartupDisk(_ onChange: @escaping @MainActor @Sendable () -> Void) -> FileSystemWatcher? {
        FileSystemWatcher(
            paths: ["/System/Volumes/Data"], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow), queue: .main
        ) { _ in
            Task { @MainActor in onChange() }
        }
    }
}
