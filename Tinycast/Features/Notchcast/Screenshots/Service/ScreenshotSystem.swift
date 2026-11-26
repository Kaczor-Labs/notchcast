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
    /// Each window's own picture at its chooser frame, taken before selection; a failed one is left out.
    let freezeWindows: @MainActor @Sendable ([ScreenshotWindow]) async throws -> [UInt32: CGImage]
    let cursor: @MainActor @Sendable () -> CGPoint
    let writeClipboard: @MainActor @Sendable (Data) -> Bool
    let writeText: @MainActor @Sendable (String) -> Bool
    let recognizeText: @Sendable (CGImage) async throws -> [ScreenTextLine]
    /// Pays Vision's one-off model compile in the background; it logs its result and never throws.
    let warmTextRecognition: @Sendable () async -> Void
    let openScreenRecordingSettings: @MainActor @Sendable () -> Void
    let downloads: @Sendable () throws -> URL
    /// The system save panel for Save As; nil when it is cancelled.
    let chooseSaveFile: @MainActor @Sendable (_ suggestedName: String) -> URL?
    /// Shows the selection surface over the windows and the ids with a still; closing it answers nil.
    let select: @MainActor @Sendable (
        [ScreenshotFrozenDisplay], [ScreenshotWindow], Set<UInt32>, @escaping @MainActor (ScreenshotRequest?) -> Void
    ) -> @MainActor () -> Void
    /// Opens the editor on a capture, its pixels per point and its sensitive-text finder; it answers per way out.
    let edit: @MainActor @Sendable (
        CGImage, CGFloat, @escaping @MainActor (CGImage) async -> [CGRect],
        @escaping @MainActor (CaptureEditorOutcome) -> Void
    ) -> @MainActor () -> Void
    /// Pixel rects over emails, card numbers, IP addresses, keys and tokens, origin top left; takes the scale.
    let findSensitiveText: @Sendable (CGImage, CGFloat) async throws -> [CGRect]
}
