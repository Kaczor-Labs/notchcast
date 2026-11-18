import Foundation

/// The system side of noise control, injected so a harness can fake it; `.live` is in `+Live`.
struct NoiseControlSystem: Sendable {
    /// The default output's CoreAudio model UID when it is a Bluetooth device, else nil.
    let outputModelUID: @MainActor @Sendable () -> String?
    /// The returned object keeps the observation alive; dropping it removes the listener.
    let watchOutput: @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> AnyObject?
    let switcher: NoiseControlSwitcher
}
