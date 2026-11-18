import Foundation

/// The system side, injected so a harness touches nothing real; `.live` is in `+Live`.
struct SystemToolsSystem: Sendable {
    let ownPID: Int32
    let processorCount: Int
    /// Monotonic, for the CPU interval between two readings.
    let uptimeNanoseconds: @Sendable () -> UInt64
    let readProcesses: @MainActor @Sendable () async -> [ProcessSample]
    /// Quits, or force quits, the very process the sample names; false when it is gone or refused.
    let signal: @MainActor @Sendable (_ sample: ProcessSample, _ force: Bool) -> Bool
    /// Shows the picker over a session; the returned closure closes it.
    let presentPicker: @MainActor @Sendable (KillProcessSession, NotchcastSurfaces) -> @MainActor () -> Void
    /// `networkQuality -c`'s output; cancelling the task ends the tool.
    let runNetworkQuality: @Sendable () async throws -> Data
}
