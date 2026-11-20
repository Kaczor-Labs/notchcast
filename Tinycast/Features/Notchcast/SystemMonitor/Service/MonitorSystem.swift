import Foundation

/// The Mac as the module sees it: one read, a sleep and the core count, so a harness can fake all three.
struct MonitorSystem: Sendable {
    /// `detail` adds what only the page shows: network counters and the process walk.
    var read: @Sendable (_ detail: Bool) async -> MonitorReading
    var sleep: @Sendable (Duration) async throws -> Void
    var processorCount: Int
}
