import Carbon.HIToolbox

/// Secure Input for as long as a hidden field's dialog is key, whichever field shows the text.
struct SecureInputHold {
    private(set) var isHeld = false
    var enable: () -> Void = { _ = EnableSecureEventInput() }
    var disable: () -> Void = { _ = DisableSecureEventInput() }

    /// The system counts enables, so each one is paired with exactly one disable.
    mutating func set(_ held: Bool) {
        guard held != isHeld else { return }
        isHeld = held
        if held { enable() } else { disable() }
    }
}
