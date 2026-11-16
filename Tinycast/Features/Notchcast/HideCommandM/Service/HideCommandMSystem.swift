import Foundation

/// The system side of ⌘M, injected so a harness can fake it; `.live` is in `+Live`.
struct HideCommandMSystem: Sendable {
    let ownPID: Int32
    let frontmost: @MainActor @Sendable () -> HideCommandMTarget?
    let commandCharacter: @MainActor @Sendable (Int) -> String?
    let hasWindows: @MainActor @Sendable (Int32) -> Bool
    let hide: @MainActor @Sendable (Int32) -> Bool
    let replay: @MainActor @Sendable (_ pid: Int32, _ keyCode: Int) -> Void
}
