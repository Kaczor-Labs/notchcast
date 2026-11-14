import IslandCore
import SwiftUI

/// The expanded view's grid as a browser lays it out: three columns, an optional spanning bottom
/// row, every length in Gecko's 1/60 px layout units. Boxes are in the grid's own coordinates.
struct ExpandedGrid: Equatable {
    struct Box: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The expanded slot's width, padding included.
    var slotWidth: Double
    /// The slot's padding: where the grid starts in the expanded slot.
    var left: Double
    var top: Double
    var width: Double
    var height: Double
    var centerTop: Double
    var bottomInset: Double
    /// Each region's content, laid out on its own.
    var sizes: PerRegion<CGSize>
    var boxes: PerRegion<Box>

    /// The grid for regions of these natural sizes, nil for an empty region.
    init(sizes: PerRegion<CGSize>, screenWidth: Double, metrics: IslandMetrics) {
        let e = metrics.expanded
        self.sizes = sizes
        slotWidth = layoutUnit(expandedWidth(screenWidth: screenWidth, metrics: metrics))
        left = layoutUnit(e.padding.side)
        top = layoutUnit(e.padding.top)
        width = slotWidth - left - layoutUnit(e.padding.trailing ?? e.padding.side)
        bottomInset = layoutUnit(e.bottomInset)
        let placement = expandedCenterPlacement(metrics: metrics)
        let centerTop = layoutUnit(placement.top)
        self.centerTop = centerTop
        let shift = layoutUnit(placement.shift)
        let gap = layoutUnit(expandedColumnGap)
        let rowGap = sizes[.bottom] != nil ? layoutUnit(e.rowGap) : 0
        func size(_ region: ExpandedRegion) -> CGSize { sizes[region] ?? .zero }
        let clientWidth = jsRound(left + width) - jsRound(left)
        let columns = expandedColumns(
            leading: size(.leading).width, center: size(.center).width, trailing: size(.trailing).width,
            innerWidth: clientWidth)
        let (c1, c3) = (layoutUnit(columns.leading), layoutUnit(columns.trailing))
        let fr = max(0, width - c1 - c3 - 2 * gap)
        let row = [
            sizes[.leading]?.height, centerTop + (sizes[.center]?.height ?? 0), sizes[.trailing]?.height,
        ].compactMap { $0 }.max() ?? 0
        height = row + (sizes[.bottom].map { rowGap + $0.height } ?? 0)
        boxes = PerRegion()
        if let lead = sizes[.leading] { boxes[.leading] = Box(x: 0, y: 0, width: c1, height: lead.height) }
        if let center = sizes[.center] {
            boxes[.center] = Box(x: c1 + gap + shift, y: 0, width: fr, height: centerTop + center.height)
        }
        // justify-self: end aligns unsafely: a region wider than its column overflows to the start.
        if let trail = sizes[.trailing] {
            let x = c1 + 2 * gap + fr + c3 - trail.width
            boxes[.trailing] = Box(x: x, y: 0, width: trail.width, height: trail.height)
        }
        if let bottom = sizes[.bottom] {
            boxes[.bottom] = Box(x: 0, y: row + rowGap, width: c1 + fr + c3 + 2 * gap, height: bottom.height)
        }
    }

    /// Where a region's content sits in its box, and how wide it is drawn.
    func content(_ region: ExpandedRegion) -> Box? {
        guard let box = boxes[region], let size = sizes[region] else { return nil }
        switch region {
        case .leading, .trailing:
            return Box(x: 0, y: 0, width: min(size.width, box.width), height: size.height)
        case .center:
            let width = min(size.width, box.width)
            return Box(x: (box.width - width) / 2, y: centerTop, width: width, height: size.height)
        case .bottom:
            return Box(x: bottomInset, y: 0, width: max(0, box.width - 2 * bottomInset), height: size.height)
        }
    }

    /// The grid's used height as `getComputedStyle` reports it: six significant digits.
    var usedHeight: Double { Double(String(format: "%.6g", height)) ?? height }

    /// Each region's centre in the expanded slot, from whole-pixel offsets as `offsetLeft` and
    /// `offsetWidth` give them.
    var centres: PerRegion<Vec> {
        var centres = PerRegion<Vec>()
        for region in ExpandedRegion.allCases {
            guard let box = boxes[region] else { continue }
            let (x, y) = (left + box.x, top + box.y)
            let width = jsRound(x + box.width) - jsRound(x)
            let height = jsRound(y + box.height) - jsRound(y)
            centres[region] = Vec(x: jsRound(x) + width / 2, y: jsRound(y) + height / 2)
        }
        return centres
    }
}

/// A CSS length on Gecko's app-unit grid, before device-pixel rasterization.
func layoutUnit(_ value: Double) -> Double {
    (value * 60).rounded() / 60
}

