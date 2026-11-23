// Adapted from RemoveMacAI (omlahore, 12cef18, MIT).
struct MacTweakSnapshot: Codable, Sendable {
    let states: [MacTweak.ID: MacTweakState]
    let journaled: Set<MacTweak.ID>

    var applied: Set<MacTweak.ID> {
        Set(states.compactMap { $0.value == .applied ? $0.key : nil })
    }
}
