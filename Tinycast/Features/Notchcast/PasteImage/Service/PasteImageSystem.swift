import Foundation

/// The system side of the paste, injected so a harness can fake it; `.live` is in `+Live`.
struct PasteImageSystem: Sendable {
    /// Finder's pid while it is the front app, else nil.
    let frontFinder: @MainActor @Sendable () -> Int32?
    let commandCharacter: @MainActor @Sendable (Int) -> String?
    /// Read on the tap thread, and only for a plain ⌘V while Finder is in front.
    let clipboardTypes: @Sendable () -> [String]
    let clipboardImage: @MainActor @Sendable () -> PasteImageClip?
    /// Nil when the focus cannot be read.
    let focus: @Sendable () async -> PasteImageFocus?
    /// Converts to PNG and writes it where Finder would paste, off the main actor; nil once saved.
    let save: @Sendable (PasteImageClip, Date) async -> PasteImageFailure?
    /// Posts ⌘V back to whatever holds the keys, tagged so no tap of ours takes it again.
    let replay: @MainActor @Sendable (_ keyCode: Int) -> Void
    let openAutomationSettings: @MainActor @Sendable () -> Void
}
