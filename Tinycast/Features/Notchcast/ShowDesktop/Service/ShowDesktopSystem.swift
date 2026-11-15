import Foundation

/// The system side of F3, injected so a harness can fake it; `.live` is in `+Live`.
struct ShowDesktopSystem: Sendable {
    let standardFunctionKeys: @MainActor @Sendable () -> Bool
    /// Where System Settings announces a flipped F-key mode; a harness passes its own center.
    let preferenceCenter: NotificationCenter
    /// The Dock toggles: a second call brings the windows back.
    let toggleDesktop: @MainActor @Sendable () -> Void
}
