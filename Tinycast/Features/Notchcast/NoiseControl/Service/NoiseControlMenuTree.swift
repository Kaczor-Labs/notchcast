import Foundation

/// The Sound menu read through injected accessors, so a harness walks a fake tree on a fake clock.
nonisolated struct NoiseControlMenuTree<Node> {
    struct Item {
        let element: Node
        let button: NoiseControlButton
    }

    /// Runs on every node before its first read; live sets that element's own AX timeout here.
    let prepare: (Node) -> Void
    let children: (Node) -> [Node]
    let identifier: (Node) -> String?
    let labels: (Node) -> [String]
    let canPress: (Node) -> Bool
    let selected: (Node) -> Bool?
    let now: () -> Duration
    var walkLimit = 600

    /// The first of `nodes` whose identifier is `wanted`; nil once the deadline passes.
    func first(identifier wanted: String, in nodes: [Node], deadline: Duration) -> Node? {
        for node in nodes {
            guard now() < deadline else { return nil }
            prepare(node)
            if identifier(node) == wanted { return node }
        }
        return nil
    }

    /// The first sibling run with Transparency or Noise Cancellation; Spatial Audio's Off is not one.
    func items(in windows: [Node], deadline: Duration) -> [Item] {
        var pending = windows[...]
        pending.forEach(prepare)
        var visited = 0
        while let parent = pending.popFirst(), visited < walkLimit, now() < deadline {
            var run: [Item] = []
            for child in children(parent) {
                guard visited < walkLimit, now() < deadline else { break }
                visited += 1
                prepare(child)
                pending.append(child)
                let item = item(child)
                if let item, !run.contains(where: { $0.button.mode == item.button.mode }) {
                    run.append(item)
                    continue
                }
                if Self.isNoiseControl(run) { return run }
                run = item.map { [$0] } ?? []
            }
            if Self.isNoiseControl(run) { return run }
        }
        return []
    }

    /// Once modes showed, close only while they still show: never reopen it or shut another window.
    func soundMenuOpen(windows: [Node], sawModes: Bool, deadline: Duration) -> Bool {
        sawModes ? !items(in: windows, deadline: deadline).isEmpty : !windows.isEmpty
    }

    private func item(_ node: Node) -> Item? {
        let labels = labels(node)
        guard let mode = NoiseControlMode.allCases.first(where: { labels.contains($0.menuTitle) }), canPress(node)
        else { return nil }
        return Item(element: node, button: NoiseControlButton(mode: mode, selected: selected(node)))
    }

    private static func isNoiseControl(_ run: [Item]) -> Bool {
        run.contains { $0.button.mode == .transparency || $0.button.mode == .noiseCancellation }
    }
}
