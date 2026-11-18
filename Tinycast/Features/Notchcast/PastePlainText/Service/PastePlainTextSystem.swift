import Foundation

/// The system side of the command, injected so a harness can fake it; `.live` is in `+Live`.
struct PastePlainTextSystem: Sendable {
    let makeBoard: @MainActor @Sendable () -> any PlainPasteBoard
    let sendPaste: @MainActor @Sendable () -> Void
    let after: @MainActor @Sendable (Duration, @escaping @MainActor () -> Void) -> Void
}
