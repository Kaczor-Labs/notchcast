// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlMenuTree.swift

import Foundation

/// A scripted Accessibility tree on a virtual clock: every read costs `readCost`, nothing waits.
@MainActor
final class FakeTree {
    struct Node {
        var identifier: String?
        var label: String?
        var pressable = true
        var selected: Bool?
        var children: [Int] = []
    }

    var nodes: [Int: Node] = [:]
    var clock: Duration = .zero
    var readCost: Duration = .zero
    var prepared: Set<Int> = []
    var reads = 0
    var unpreparedReads = 0

    init(_ nodes: [Int: Node]) { self.nodes = nodes }

    func read(_ id: Int) -> Node {
        reads += 1
        if !prepared.contains(id) { unpreparedReads += 1 }
        clock += readCost
        return nodes[id] ?? Node()
    }

    var tree: NoiseControlMenuTree<Int> {
        NoiseControlMenuTree(
            prepare: { self.prepared.insert($0) },
            children: { self.read($0).children },
            identifier: { self.read($0).identifier },
            labels: { self.read($0).label.map { [$0] } ?? [] },
            canPress: { self.read($0).pressable },
            selected: { self.read($0).selected },
            now: { self.clock })
    }
}

func mode(_ label: String, _ selected: Bool, children: [Int] = []) -> FakeTree.Node {
    FakeTree.Node(label: label, selected: selected, children: children)
}

func heading(_ label: String, children: [Int] = []) -> FakeTree.Node {
    FakeTree.Node(label: label, pressable: false, children: children)
}

@main
@MainActor
enum NoiseControlMenuTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        soundIcon()
        sections()
        closing()
        print("\(checks) noise control menu checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func modes(_ items: [NoiseControlMenuTree<Int>.Item]) -> [NoiseControlButton] { items.map(\.button) }

    static func soundIcon() {
        var icons = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, FakeTree.Node(identifier: "icon\($0)")) })
        icons[10] = FakeTree.Node(identifier: "sound")
        let slow = FakeTree(icons)
        slow.readCost = .seconds(1)
        check("a wedged menu bar stops the icon search at the deadline",
              slow.tree.first(identifier: "sound", in: Array(1...10), deadline: .seconds(3)) == nil && slow.reads == 3)
        check("every icon gets its timeout before it is read", slow.unpreparedReads == 0)

        let quick = FakeTree(icons)
        check("in time, the Sound icon is found", quick.tree.first(identifier: "sound", in: Array(1...10), deadline: .seconds(3)) == 10)
    }

    static func sections() {
        let nested = FakeTree([
            1: heading("window", children: [2, 3]),
            2: heading("Spatial Audio", children: [20, 21, 22]),
            20: mode("Off", true), 21: mode("Fixed", false), 22: mode("Head Tracked", false),
            3: heading("Noise Control", children: [30, 31, 32]),
            30: mode("Off", false), 31: mode("Transparency", true), 32: mode("Noise Cancellation", false),
        ])
        let found = nested.tree.items(in: [1], deadline: .seconds(3))
        check("Spatial Audio's Off above noise control is not taken for it", modes(found) == [
            NoiseControlButton(mode: .off, selected: false), NoiseControlButton(mode: .transparency, selected: true),
            NoiseControlButton(mode: .noiseCancellation, selected: false),
        ] && found.first?.element == 30)
        check("every menu item gets its timeout before it is read", nested.unpreparedReads == 0)

        let flat = FakeTree([
            1: heading("window", children: [10, 11, 12, 13, 14, 15, 16, 17]),
            10: heading("Spatial Audio"), 11: mode("Off", true), 12: mode("Fixed", false),
            13: heading("Noise Control"), 14: mode("Off", false), 15: mode("Adaptive", true), 16: mode("Transparency", false),
            17: heading("Volume"),
        ])
        check("in one flat list, the run next to Transparency is noise control",
              flat.tree.items(in: [1], deadline: .seconds(3)).map(\.element) == [14, 15, 16])

        let spatialOnly = FakeTree([1: heading("window", children: [2, 3]), 2: mode("Off", true), 3: mode("Fixed", false)])
        check("an Off with no noise control beside it is no noise control",
              spatialOnly.tree.items(in: [1], deadline: .seconds(3)).isEmpty)

        let slow = FakeTree([1: heading("window", children: [2]), 2: heading("group", children: [3]), 3: mode("Transparency", true)])
        slow.readCost = .seconds(1)
        check("a slow menu stops the walk at the deadline", slow.tree.items(in: [1], deadline: .seconds(2)).isEmpty)
    }

    static func closing() {
        let menus = FakeTree([
            1: heading("Sound", children: [10, 11]), 10: mode("Off", false), 11: mode("Transparency", true),
            2: heading("Wi-Fi", children: [20]), 20: mode("Network", false),
        ])
        let tree = menus.tree
        check("the Sound menu still showing its modes is closed",
              tree.soundMenuOpen(windows: [2, 1], sawModes: true, deadline: .seconds(1)))
        check("another Control Center window is left alone", !tree.soundMenuOpen(windows: [2], sawModes: true, deadline: .seconds(1)))
        check("a menu already shut is not reopened", !tree.soundMenuOpen(windows: [], sawModes: true, deadline: .seconds(1)))
        check("a menu that never showed modes is closed while open",
              tree.soundMenuOpen(windows: [2], sawModes: false, deadline: .seconds(1))
                  && !tree.soundMenuOpen(windows: [], sawModes: false, deadline: .seconds(1)))
    }
}
