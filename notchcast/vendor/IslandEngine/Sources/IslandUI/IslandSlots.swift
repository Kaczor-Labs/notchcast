import IslandCore
import SwiftUI

/// How a host's content becomes slot views, and the widths the island lays its shape out with.
@MainActor
public struct IslandSlots<Content, Slot: View> {
    public let metrics: IslandMetrics
    /// The view for one slot's content.
    public let view: @MainActor (Content) -> Slot

    public init(metrics: IslandMetrics = .standard, view: @escaping @MainActor (Content) -> Slot) {
        self.metrics = metrics
        self.view = view
    }

    /// Lays out the presentation's slots in a container `stageWidth` wide and reads their widths, the
    /// expanded grid's height and its regions' centres, as upstream measures its slots after layout.
    public func measure(_ presentation: IslandPresentation<Content>, stageWidth: Double) -> ContentMeasures {
        switch presentation {
        case .idle:
            return ContentMeasures()
        case .expanded(let content):
            let grid = grid(content, stageWidth: stageWidth)
            return ContentMeasures(expandedHeight: grid.usedHeight, regions: grid.centres)
        case .compact(let content):
            return ContentMeasures(
                leading: width(content.leading, .compact, .leading), trailing: width(content.trailing, .compact, .trailing))
        case .minimal(let attached, let detached, let split):
            return ContentMeasures(
                attached: width(attached, .minimal, .attached), detached: width(detached, .minimal, .detached),
                split: split.map {
                    ContentMeasure.Split(
                        attached: SlotPair(
                            leading: width($0.attached.leading, .minimal, .splitAttachedLeading),
                            trailing: width($0.attached.trailing, .minimal, .splitAttachedTrailing)),
                        detached: SlotPair(
                            leading: width($0.detached.leading, .minimal, .splitDetachedLeading),
                            trailing: width($0.detached.trailing, .minimal, .splitDetachedTrailing)))
                })
        }
    }

    /// The box a slot of `kind` lays its content out in.
    func box(_ kind: SlotBox.Kind, cap: Double? = nil) -> SlotBox {
        switch kind {
        case .compact: SlotBox(height: metrics.compact.height, maxWidth: cap ?? metrics.compact.maxSlotWidth, clipsAcross: true)
        case .minimal: SlotBox(height: metrics.minimal.height, maxWidth: cap, clipsAcross: cap != nil)
        }
    }

    /// The expanded grid `content` lays out in a container `stageWidth` wide.
    func grid(_ content: ExpandedContent<Content>, stageWidth: Double) -> ExpandedGrid {
        // Upstream mounts the top row's regions even when empty; only the bottom one comes and goes.
        var sizes = PerRegion<CGSize>([
            .leading: size(content.leading, .expandedLeading), .center: size(content.center, .expandedCenter),
            .trailing: size(content.trailing, .expandedTrailing),
        ])
        sizes[.bottom] = content.bottom.map { size($0, .expandedBottom) }
        let screenWidth = islandScreenWidth(containerWidth: stageWidth, metrics: metrics)
        let natural = ExpandedGrid(sizes: sizes, screenWidth: screenWidth, metrics: metrics)
        for (region, content, name) in [
            (ExpandedRegion.leading, content.leading, SlotName.expandedLeading),
            (.center, content.center, .expandedCenter), (.trailing, content.trailing, .expandedTrailing),
            (.bottom, content.bottom, .expandedBottom),
        ] {
            guard let content, let placed = natural.content(region) else { continue }
            let measured = size(view(content).environment(\.islandSlot, name), width: placed.width)
            sizes[region]?.height = measured.height
        }
        return ExpandedGrid(sizes: sizes, screenWidth: screenWidth, metrics: metrics)
    }

    private func width(_ content: Content?, _ kind: SlotBox.Kind, _ name: SlotName) -> Double {
        guard let content else { return 0 }
        let box = box(kind)
        return size(box { view(content) }.environment(\.islandSlot, name)).width
    }

    private func size(_ content: Content?, _ name: SlotName) -> CGSize {
        content.map { size(view($0).environment(\.islandSlot, name)) } ?? .zero
    }

    /// The natural size of `content`, laid out on its own.
    private func size(_ content: some View, width: Double? = nil) -> CGSize {
        // An empty root gets SwiftUI's 10-point ideal size; an empty stack has no content size.
        let renderer = ImageRenderer(content: VStack(spacing: 0) { content }.fixedSize(horizontal: width == nil, vertical: true))
        renderer.proposedSize = ProposedViewSize(width: width.map { CGFloat($0) }, height: nil)
        // Text rounds its size up to the pixel grid; Gecko lays out in 1/60 px app units.
        renderer.scale = 60
        var size = CGSize.zero
        // Layout only: the drawing callback is never called.
        renderer.render { measured, _ in size = measured }
        return size
    }
}

/// A slot's box: content in a row, centred down a fixed height, as wide as it is up to `maxWidth`.
/// A row wider than that shrinks its views to fit, as a flex row's items do.
struct SlotBox: Layout {
    enum Kind {
        case compact
        case minimal
    }

    var height: Double
    var maxWidth: Double?
    /// Whether content past the right edge is cut, across only.
    var clipsAcross: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        return CGSize(width: min(natural, maxWidth ?? .infinity), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let room = max(0, bounds.maxX - x)
            let width = min(subview.sizeThatFits(.unspecified).width, room)
            let offer = ProposedViewSize(width: width, height: nil)
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: offer)
            x += subview.sizeThatFits(offer).width
        }
    }
}
