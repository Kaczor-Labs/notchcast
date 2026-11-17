import CoreGraphics
import IslandCore

extension IslandLayout {
    /// One top for idle, compact and expanded, so the pill never jumps as it grows.
    func applyTops(to metrics: inout IslandMetrics) {
        metrics.top = top
        metrics.expanded.top = top
        metrics.expanded.padding = .init(top: expandedPadding, side: 0, bottom: 0)
    }
}
