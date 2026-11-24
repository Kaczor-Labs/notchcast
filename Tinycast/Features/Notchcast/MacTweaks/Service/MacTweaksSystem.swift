import Foundation

struct MacTweaksSystem: Sendable {
    struct Reading: Sendable {
        let stored: MacTweakValue?
        let effective: MacTweakValue?
        var managed = false
        var heldElsewhere: MacTweakHeldElsewhere?

        // Our own layer wins over every fallback layer, never over this Mac's or a profile's.
        var block: MacTweakState? {
            if managed { return .managed }
            return heldElsewhere == .thisMac ? .heldElsewhere(.thisMac) : nil
        }

        // A fallback layer blocks only a switch it already holds on, as Peel's TweakStore.heldElsewhere.
        func block(wanting value: MacTweakValue) -> MacTweakState? {
            if let block { return block }
            guard stored == nil, let heldElsewhere, value.matches(effective) else { return nil }
            return .heldElsewhere(heldElsewhere)
        }
    }

    let version: OperatingSystemVersion
    let journalFolder: URL
    let read: @Sendable (MacTweakTarget) throws -> Reading
    let readAll: @Sendable ([MacTweakTarget]) -> [MacTweakTarget: Result<Reading, any Error>]
    let write: @Sendable (MacTweakTarget, MacTweakValue?) throws -> Void
    let restart: @Sendable (MacTweakRestart) throws -> Void
    let now: @Sendable () -> Date
}
