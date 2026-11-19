import Foundation

/// A running capture; `stop` finishes its file, and a capture that ends on its own reports once.
@MainActor
protocol RecordingCapture: AnyObject {
    func stop() async throws
}

/// The Mac side of Screen Recording, injected so a harness fakes it; `.live` is in `+Live`.
struct RecordingSystem: Sendable {
    /// Asks once when not yet granted; true only with Screen Recording access.
    let grantScreen: @MainActor @Sendable () -> Bool
    let grantMicrophone: @MainActor @Sendable () async -> Bool
    let displayUnderCursor: @MainActor @Sendable () -> UInt32?
    /// Shows the selection surface; the returned closure closes it, which answers nil.
    let select: @MainActor @Sendable (
        RecordingKind, @escaping @MainActor (RecordingTarget?) -> Void
    ) -> @MainActor () -> Void
    /// Writes to `file` until stopped; `ended` runs if the capture stops by itself (a window closed).
    let start: @MainActor @Sendable (
        RecordingTarget, RecordingOptions, _ file: URL, _ ended: @escaping @MainActor (any Error) -> Void
    ) async throws -> any RecordingCapture
    /// Runs `tick` about once a second until the returned closure cancels it.
    let everySecond: @MainActor @Sendable (_ tick: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    /// This run's own folder, where unfinished clips live.
    let workFolder: @Sendable () throws -> URL
    /// The work folders of runs that ended, never one a running copy still writes to.
    let abandonedWorkFolders: @Sendable () -> [URL]
    let desktop: @Sendable () throws -> URL
    /// Holds off idle sleep until the returned closure runs.
    let keepAwake: @MainActor @Sendable () -> @MainActor () -> Void
    /// Space left where clips are written.
    let freeBytes: @Sendable () async -> Int64
    let duration: @Sendable (URL) async throws -> TimeInterval
    /// Whether the clip can be cut without re-encoding into the given container.
    let passthroughWorks: @Sendable (URL, RecordingOptions.Container) async -> Bool
    let export: @Sendable (_ source: URL, RecordingTrim, RecordingExport, _ to: URL) async throws -> Void
    /// Shows the trimmer; the returned closure closes it without an answer.
    let trim: @MainActor @Sendable (
        _ clip: URL, TimeInterval, @escaping @MainActor (RecordingTrimmerAnswer) -> Void
    ) -> @MainActor () -> Void
    let writeClipboard: @MainActor @Sendable (URL) -> Bool
    let reveal: @MainActor @Sendable (URL) -> Void
}
