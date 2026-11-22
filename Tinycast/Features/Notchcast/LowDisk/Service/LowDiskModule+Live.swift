import CoreGraphics
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

    static func waitForCheck(_ interval: Duration) async throws {
        try await Task.sleep(for: interval, tolerance: interval == LowDiskPolicy.checkInterval ? .seconds(60) : .seconds(2))
    }
}
