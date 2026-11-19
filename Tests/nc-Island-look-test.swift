// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift
import Foundation

@main
struct IslandLookTest {
    @MainActor static func main() {
        let suite = "nc-island-look-test-\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(IslandLook.standard(hasNotch: true) == .black, "A notch defaults to Black")
        precondition(IslandLook.standard(hasNotch: false) == .frosted, "No notch defaults to Frosted")

        let store = IslandLookStore(defaults: defaults)
        precondition(store.choices.isEmpty, "A fresh suite holds no choice")
        precondition(store.look(uuid: "A", hasNotch: true) == .black, "Never set follows the notch rule")
        precondition(store.look(uuid: "B", hasNotch: false) == .frosted, "Never set without a notch is Frosted")
        precondition(store.look(uuid: nil, hasNotch: false) == .frosted, "No UUID follows the rule")

        store.set(.frosted, uuid: "A")
        store.set(.black, uuid: "B")
        store.set(.black, uuid: nil)
        precondition(store.look(uuid: "A", hasNotch: true) == .frosted, "An explicit choice beats the notch rule")
        precondition(store.look(uuid: "B", hasNotch: false) == .black, "An explicit Black sticks off the notch")
        precondition(store.choices.count == 2, "No UUID stores nothing")
        let stored = defaults.dictionary(forKey: IslandLookStore.key) as? [String: String]
        precondition(stored == ["A": "frosted", "B": "black"], "Only explicit choices are stored: \(String(describing: stored))")

        let reopened = IslandLookStore(defaults: defaults)
        precondition(reopened.choices == ["A": .frosted, "B": .black], "Choices survive a restart")
        let display = IslandLookDisplay(displayID: 7, uuid: "A", name: "Built-in", hasNotch: true)
        precondition(reopened.look(display) == .frosted, "A display reads its UUID's choice")

        defaults.set(["A": "glass", "B": 3, "C": "black"], forKey: IslandLookStore.key)
        precondition(IslandLookStore(defaults: defaults).choices == ["C": .black], "Bad entries count as never set")
        defaults.set("frosted", forKey: IslandLookStore.key)
        precondition(IslandLookStore(defaults: defaults).choices.isEmpty, "A non-dictionary counts as never set")
        precondition(IslandLookStore.decode(nil).isEmpty, "Nothing stored decodes to nothing")

        precondition(IslandKeyline.width(scale: 2) == 0.5, "Black's line stays one device pixel")
        precondition(IslandKeyline.width(scale: 2, look: .frosted) == 1, "Frosted's edge is one point")
        precondition(IslandKeyline.restingStrength(look: .frosted, hasNotch: false) == 1, "The Frosted pill keeps its edge")
        precondition(IslandKeyline.restingStrength(look: .frosted, hasNotch: true) == 0, "No edge round the bare notch")
        precondition(IslandKeyline.restingStrength(look: .black, hasNotch: false) == 0, "Black has no edge at rest")
        precondition(IslandKeyline.strength(growth: 0, enabled: true, resting: 1) == 1, "A resting edge is full")
        precondition(IslandKeyline.strength(growth: 8, enabled: true) == 0.5, "Growth still ramps the line")
        precondition(IslandKeyline.strength(growth: 0, enabled: false, resting: 1) == 0, "The setting off draws none")
        print("Island look: notch rule default, explicit choices stored by UUID, bad data ignored, edge strengths")
    }
}
