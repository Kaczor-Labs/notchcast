import Foundation

/// A scheduled step the module calls off when a newer paste or `stop` overtakes it.
protocol PlainPasteTimer {
    func cancel()
}

/// The system side of the command, injected so a harness can fake it; `.live` is in `+Live`.
struct PastePlainTextSystem: Sendable {
    let makeBoard: @MainActor @Sendable () -> any PlainPasteBoard
    let postCommandV: @MainActor @Sendable () -> Void
    /// True while ⌘, ⌥, ⇧ or ⌃ is down, so ⌘V waits for the hotkey's keys to come up.
    let modifiersHeld: @MainActor @Sendable () -> Bool
    /// Presses the front app's own ⌥⇧⌘V menu item; false when it has none.
    let pressMatchStyle: @MainActor @Sendable () -> Bool
    let now: @MainActor @Sendable () -> ContinuousClock.Instant
    let after: @MainActor @Sendable (Duration, @escaping @MainActor () -> Void) -> any PlainPasteTimer
}
