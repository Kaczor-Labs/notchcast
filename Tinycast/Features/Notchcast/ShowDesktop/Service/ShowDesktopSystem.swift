import Foundation

/// The system side of F3, injected so a harness can fake it; `.live` is in `+Live`.
struct ShowDesktopSystem: Sendable {
    let standardFunctionKeys: @MainActor @Sendable () -> Bool
    /// The Dock toggles: a second call brings the windows back.
    let toggleDesktop: @MainActor @Sendable () -> Void
}
