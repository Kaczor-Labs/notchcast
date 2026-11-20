import CoreGraphics
import Foundation

/// The Mac side of Screenshots, injected so a harness fakes it; `.live` is in `+Live`.
struct ScreenshotSystem: Sendable {
    /// Asks once when not yet granted; true only with Screen Recording access.
    let grantAccess: @MainActor @Sendable () -> Bool
    /// Every display, or only the one holding the point, captured in one pass without `exclusion`.
    let freeze: @MainActor @Sendable (_ under: CGPoint?, _ exclusion: ScreenshotExclusion) async throws
        -> [ScreenshotFrozenDisplay]
    let windows: @MainActor @Sendable () -> [ScreenshotWindow]
    /// Each window's own picture, taken before selection; a window that fails to capture is left out.
    let freezeWindows: @MainActor @Sendable ([UInt32]) async throws -> [UInt32: CGImage]
    let cursor: @MainActor @Sendable () -> CGPoint
    let writeClipboard: @MainActor @Sendable (Data) -> Bool
    let writeText: @MainActor @Sendable (String) -> Bool
    let recognizeText: @Sendable (CGImage) async throws -> [ScreenTextLine]
    /// Pays Vision's one-off model compile in the background; it logs its result and never throws.
    let warmTextRecognition: @Sendable () async -> Void
    let openScreenRecordingSettings: @MainActor @Sendable () -> Void
    let desktop: @Sendable () throws -> URL
    /// Shows the selection surface; the returned closure closes it, which answers nil.
    let select: @MainActor @Sendable (
        [ScreenshotFrozenDisplay], [ScreenshotWindow], @escaping @MainActor (ScreenshotRequest?) -> Void
    ) -> @MainActor () -> Void
    /// Opens the editor on a capture and its pixels per point; it answers per Copy, Save or Escape.
    let edit: @MainActor @Sendable (CGImage, CGFloat, @escaping @MainActor (CaptureEditorOutcome) -> Void)
        -> @MainActor () -> Void
}
