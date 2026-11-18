import Foundation

/// The system side of the paste, injected so a harness can fake it; `.live` is in `+Live`.
struct PasteImageSystem: Sendable {
    /// Finder's pid while it is the front app, else nil.
    let frontFinder: @MainActor @Sendable () -> Int32?
    let commandCharacter: @MainActor @Sendable (Int) -> String?
    /// Read on the tap thread, and only for a plain ⌘V while Finder is in front.
    let clipboardTypes: @Sendable () -> [String]
    let clipboardImage: @MainActor @Sendable () -> PasteImageClip?
    let focusedRole: @Sendable (_ pid: Int32) async -> String?
    /// Converts to PNG and has Finder place it, off the main actor; false on any failure.
    let save: @Sendable (PasteImageClip, Date) async -> Bool
    let replay: @MainActor @Sendable (_ pid: Int32, _ keyCode: Int) -> Void
}
