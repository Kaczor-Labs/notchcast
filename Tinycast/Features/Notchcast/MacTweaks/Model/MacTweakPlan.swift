// Adapted from RemoveMacAI (omlahore, 12cef18, MIT).
enum MacTweakPreset: String, CaseIterable, Sendable {
    case recommended, maximumPrivacy

    func wanted(in catalogue: [MacTweak]) -> Set<MacTweak.ID> {
        let presets: Set<Self> = self == .maximumPrivacy ? [.recommended, .maximumPrivacy] : [.recommended]
        let selected = catalogue.filter { !$0.presets.isDisjoint(with: presets) }
        return Set(selected.map(\.id))
    }
}

struct MacTweakSnapshot: Sendable {
    let states: [MacTweak.ID: MacTweakState]
    let journaled: Set<MacTweak.ID>
}

struct MacTweakPlan: Sendable {
    var apply: [MacTweak] = []
    var restore: Set<MacTweak.ID> = []
    var clear: [MacTweak] = []

    static func make(
        wanted: Set<MacTweak.ID>,
        catalogue: [MacTweak],
        snapshot: MacTweakSnapshot
    ) -> Self {
        var plan = Self()
        for tweak in catalogue {
            guard let state = snapshot.states[tweak.id], state.canChange else { continue }
            if wanted.contains(tweak.id), state != .applied {
                plan.apply.append(tweak)
            } else if !wanted.contains(tweak.id), snapshot.journaled.contains(tweak.id) {
                plan.restore.insert(tweak.id)
            }
            if !wanted.contains(tweak.id), state == .applied || state == .partial {
                plan.clear.append(tweak)
            }
        }
        return plan
    }
}
