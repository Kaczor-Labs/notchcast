import Foundation

struct MacTweaksSystem: Sendable {
    struct Reading: Sendable {
        let stored: MacTweakValue?
        let effective: MacTweakValue?
        var managed = false
        var heldElsewhere: MacTweakHeldElsewhere?

        var block: MacTweakState? {
            if managed { return .managed }
            return heldElsewhere.map(MacTweakState.heldElsewhere)
        }
    }

    let version: OperatingSystemVersion
    let journalFolder: URL
    let read: @Sendable (MacTweakTarget) throws -> Reading
    let write: @Sendable (MacTweakTarget, MacTweakValue?) throws -> Void
    let restart: @Sendable (MacTweakRestart) throws -> Void
    let now: @Sendable () -> Date
}
