import Foundation

/// The helper's contract-4 verbs this add-on may send; the raw values are the helper's own spelling.
enum KeepAwakeSleepVerb: String, Codable, Sendable {
    /// `pmset -a disablesleep 0`: closing the lid sleeps the Mac again.
    case batterySleepOn = "battery-sleep-on"
    /// `pmset -a disablesleep 1`
    case batterySleepOff = "battery-sleep-off"
}

enum LidClosedPolicy {
    static func plan(enabled: Bool, helperReady: Bool, keepAwakeHolding: Bool) -> KeepAwakeSleepVerb {
        enabled && helperReady && keepAwakeHolding ? .batterySleepOff : .batterySleepOn
    }
}
