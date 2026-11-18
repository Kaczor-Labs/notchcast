import Foundation

/// The system side of Finder tools, injected so a harness can fake it; `.live` is in `+Live`.
struct FinderToolsSystem: Sendable {
    /// Marks the events we post, so our own tap lets them through.
    let syntheticTag: Int64
    let frontmostFinderPID: @MainActor @Sendable () -> Int32?
    let changeCount: @MainActor @Sendable () -> Int
    let commandCharacter: @MainActor @Sendable (Int) -> String?
    /// Off the main actor: Accessibility reads are cross-process calls that can stall.
    let focus: @Sendable (_ pid: Int32) async -> [FinderToolsFocus.Element]?
    let post: @MainActor @Sendable (_ pid: Int32, _ keyCode: UInt16, _ modifiers: FinderToolsPolicy.Modifiers) -> Void
}
