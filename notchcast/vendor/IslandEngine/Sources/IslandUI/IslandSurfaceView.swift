import IslandCore
import SwiftUI

/// SwiftUI's blur radius for one point of CSS `filter: blur()`, measured against Gecko at 3x.
let blurScale = 1.03

/// The island a surface draws: its keyline, black shape, content layers and sensor, on a stage as
/// wide as the surface's and tall enough for the tallest expanded shape.
public struct IslandSurfaceView<Content, Slot: View>: View {
    let surface: IslandSurface<Content>
    let slots: IslandSlots<Content, Slot>
    let hits: AnyView?
    @FocusedValue(\.islandLayer) private var focusedLayer

    public init(surface: IslandSurface<Content>, slots: IslandSlots<Content, Slot>) {
        self.init(surface: surface, slots: slots, hits: nil)
    }

    init(surface: IslandSurface<Content>, slots: IslandSlots<Content, Slot>, hits: AnyView?) {
        self.surface = surface
        self.slots = slots
        self.hits = hits
    }

    public var body: some View {
        let metrics = slots.metrics
        let shape = surface.shape
        let stage = surface.stage
        let width = islandScreenWidth(containerWidth: surface.stageWidth, metrics: metrics)
        let parts = [shape.paths.pill, shape.paths.bridge, shape.paths.bubble].filter { !$0.isEmpty }
        let keyline = (stage.shadow.keyline * 1000).rounded() / 1000
        let outline = ZStack(alignment: .topLeading) {
            ForEach(parts.indices, id: \.self) { index in
                Path(parts[index].cgPath).stroke(
                    .white.opacity(keyline), style: StrokeStyle(lineWidth: metrics.keyline.width * 2, lineJoin: .round))
            }
            ForEach(parts.indices, id: \.self) { index in
                Path(parts[index].cgPath).fill(.black)
            }
        }
        .frame(width: width, height: stageHeight(metrics), alignment: .topLeading)
        ZStack(alignment: .topLeading) {
            Group {
                IslandShadow(shadow: metrics.expanded.shadow, slopes: stage.shadow) { outline }
                outline
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            if let hits {
                hits.frame(width: width, height: stageHeight(metrics))
                    .environment(\.islandContentFocus, contentFocus)
            }
            ZStack(alignment: .topLeading) {
                ForEach(stage.layers, id: \.key.islandIdentity) { layer in
                    let leaving = !sameString(layer.key, surface.contentKey)
                    IslandLayerView(
                        layer: layer, presentation: surface.presentations[layer.key], slots: slots,
                        stageWidth: surface.stageWidth, onResize: leaving ? nil : { surface.contentResized() })
                    .contentShape(StagePath(path: shape.paths.outline))
                    .allowsHitTesting(layer.kind == .expanded && !leaving)
                    .accessibilityHidden(leaving)
                    .focusedValue(\.islandLayer, LayerFocus(surface: ObjectIdentifier(surface), key: layer.key))
                }
            }
            .frame(width: width, height: stageHeight(metrics), alignment: .topLeading)
            .clipShape(StagePath(path: shape.paths.pill.isEmpty ? nil : shape.paths.outline))
            .foregroundStyle(.white)
            .font(.system(size: 15))
            Path(sensor(metrics, width: width).cgPath).fill(.black).opacity(metrics.sensor.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width, height: stageHeight(metrics), alignment: .topLeading)
    }

    private var contentFocus: ContentFocus {
        guard let focusedLayer, focusedLayer.surface == ObjectIdentifier(surface) else { return .outside }
        return sameString(focusedLayer.key, surface.contentKey) ? .current : .leaving
    }

    private func sensor(_ metrics: IslandMetrics, width: Double) -> IslandPath {
        let idle = metrics.idle
        return .continuousRect(
            x: width / 2 - idle.width / 2 + 0.5, y: metrics.top + 0.5, width: idle.width - 1, height: idle.height - 1,
            radius: idle.height / 2 - 0.5, smoothing: metrics.corner.smoothing)
    }
}

/// The stage's height: room for the tallest expanded shape and its shadow, as upstream lays it out.
public func stageHeight(_ metrics: IslandMetrics) -> Double {
    (metrics.top + metrics.expanded.maxHeight * 1.3).rounded(.up)
}

/// One mounted layer: its root's clip over the slots of its presentation.
struct IslandLayerView<Content, Slot: View>: View {
    let layer: ContentLayer
    let presentation: IslandPresentation<Content>?
    let slots: IslandSlots<Content, Slot>
    let stageWidth: Double
    /// Called when a slot of the current layer changes size outside a store change.
    let onResize: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch presentation {
            case .compact(let content):
                slot(.leading, content.leading, .compact)
                slot(.trailing, content.trailing, .compact)
            case .minimal(let attached, let detached, let split):
                slot(.attached, attached, .minimal)
                slot(.detached, detached, .minimal)
                if let split {
                    slot(.splitAttachedLeading, split.attached.leading, .minimal)
                    slot(.splitAttachedTrailing, split.attached.trailing, .minimal)
                    slot(.splitDetachedLeading, split.detached.leading, .minimal)
                    slot(.splitDetachedTrailing, split.detached.trailing, .minimal)
                }
            case .expanded(let content):
                expanded(content, grid: slots.grid(content, stageWidth: stageWidth))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .slotStyle(style(.expandedClip))
            case .idle, nil:
                EmptyView()
            }
            ZStack(alignment: .topLeading) { echoes }
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .disabled(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .slotStyle(style(.root))
    }

    /// Each blurred slot's wide part: its copy, drawn after every slot and added to what is under it.
    @ViewBuilder
    private var echoes: some View {
        switch presentation {
        case .compact(let content):
            slot(.leading, content.leading, .compact, echo: true).blendMode(.plusLighter)
            slot(.trailing, content.trailing, .compact, echo: true).blendMode(.plusLighter)
        case .minimal(let attached, let detached, let split):
            slot(.attached, attached, .minimal, echo: true).blendMode(.plusLighter)
            slot(.detached, detached, .minimal, echo: true).blendMode(.plusLighter)
            if let split {
                slot(.splitAttachedLeading, split.attached.leading, .minimal, echo: true).blendMode(.plusLighter)
                slot(.splitAttachedTrailing, split.attached.trailing, .minimal, echo: true).blendMode(.plusLighter)
                slot(.splitDetachedLeading, split.detached.leading, .minimal, echo: true).blendMode(.plusLighter)
                slot(.splitDetachedTrailing, split.detached.trailing, .minimal, echo: true).blendMode(.plusLighter)
            }
        case .expanded(let content):
            if let echo = style(.expandedClip).echo {
                expanded(content, grid: slots.grid(content, stageWidth: stageWidth), echo: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .slotStyle(style(.expandedClip))
                    .blur(radius: echo.blur * blurScale)
                    .blendMode(.plusLighter)
            }
        case .idle, nil:
            EmptyView()
        }
    }

    private func style(_ name: SlotName) -> SlotStyle {
        layer.slots[name] ?? SlotStyle()
    }

    /// The style a slot's copy draws with: the slot's own, at the copy's opacity and blur.
    private func echoStyle(_ name: SlotName) -> SlotStyle? {
        guard var style = layer.slots[name], let echo = style.echo else { return nil }
        style.opacity = echo.opacity
        style.blur = echo.blur
        return style
    }

    /// The expanded slot: the grid's regions, each placed at its box and styled about its centre.
    private func expanded(_ content: ExpandedContent<Content>, grid: ExpandedGrid, echo: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            region(.expandedLeading, .leading, content.leading, grid, echo: echo)
            region(.expandedCenter, .center, content.center, grid, echo: echo)
            region(.expandedTrailing, .trailing, content.trailing, grid, echo: echo)
            region(.expandedBottom, .bottom, content.bottom, grid, echo: echo)
        }
        .frame(width: grid.slotWidth, alignment: .topLeading)
        .slotStyle(style(.expanded))
    }

    @ViewBuilder
    private func region(
        _ name: SlotName, _ region: ExpandedRegion, _ content: Content?, _ grid: ExpandedGrid, echo: Bool
    ) -> some View {
        if let box = grid.boxes[region], let placed = grid.content(region),
            let style = echo ? echoStyle(name) : style(name)
        {
            ZStack(alignment: .topLeading) {
                if let content {
                    IdealSizeBox(size: CGSize(width: placed.width, height: placed.height)) { slots.view(content) }
                        .environment(\.islandSlot, name)
                        .onGeometryChange(for: CGSize.self, of: \.size) { _ in if !echo { onResize?() } }
                        .frame(width: placed.width, height: placed.height, alignment: .topLeading)
                        .offset(x: placed.x, y: placed.y)
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .slotStyle(style)
            .offset(x: grid.left + box.x, y: grid.top + box.y)
        }
    }

    @ViewBuilder
    private func slot(_ name: SlotName, _ content: Content?, _ kind: SlotBox.Kind, echo: Bool = false) -> some View {
        if let content, let style = echo ? echoStyle(name) : style(name) {
            let box = slots.box(kind, cap: style.maxWidth)
            box { slots.view(content) }
                .environment(\.islandSlot, name)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { _ in
                    if !echo && name != .attached && name != .detached { onResize?() }
                }
                // Top, not centred in the pixel-rounded frame, or a transform rounds a block down.
                .frame(height: box.height, alignment: .top)
                .clipShape(AcrossClip(active: box.clipsAcross))
                .slotStyle(style)
        }
    }
}

extension View {
    /// Draws what the stage wrote on a slot, in CSS's order: filter, clip, opacity, then transform.
    func slotStyle(_ style: SlotStyle) -> some View {
        let transform = style.transform
        let blur = style.blur ?? 0
        let clip = style.clip.flatMap(slotClipPath)
        return self
            .blur(radius: blur > 0 ? blur * blurScale : 0)
            .clipShape(StagePath(path: clip))
            .opacity(style.visibility == .hidden ? 0 : style.opacity ?? 1)
            .scaleEffect(x: transform?.sx ?? 1, y: transform?.sy ?? 1, anchor: .center)
            // CSS translates in drawing coordinates; SwiftUI's offset snaps before compositing.
            .transformEffect(CGAffineTransform(translationX: transform?.x ?? 0, y: (transform?.y ?? 0) - (transform?.lift ?? 0)))
    }
}

/// A slot's clip as a path in its own points, or nil for none.
private func slotClipPath(_ clip: SlotClip) -> IslandPath? {
    switch clip {
    case .none:
        return nil
    case .path(let path):
        return path
    case .band(let reach, let top, let right, let bottom):
        let (reach, right, top, bottom) = (fixed(reach, 1), fixed(right, 1), fixed(top, 2), fixed(bottom, 2))
        return IslandPath([
            .move(Vec(x: -reach, y: top)), .line(Vec(x: right, y: top)), .line(Vec(x: right, y: bottom)),
            .line(Vec(x: -reach, y: bottom)), .close,
        ])
    case .cappedBand(let reach, let top, let capX, let rx, let ry, let bottom):
        let (reach, top, bottom) = (fixed(reach, 1), fixed(top, 2), fixed(bottom, 2))
        let (capX, rx, ry) = (fixed(capX, 2), fixed(rx, 2), fixed(ry, 2))
        return IslandPath([
            .move(Vec(x: -reach, y: top)), .line(Vec(x: capX, y: top)), .arc(rx: rx, ry: ry, to: Vec(x: capX, y: bottom)),
            .line(Vec(x: -reach, y: bottom)), .close,
        ])
    }
}

/// `value` rounded as JavaScript's `toFixed(digits)` writes it into a clip.
private func fixed(_ value: Double, _ digits: Int) -> Double {
    let unit = pow(10, Double(digits))
    return (value * unit).rounded() / unit
}

/// Lays its content out at `size` from its top-left corner but takes the content's ideal size, so
/// its geometry changes when the content wants another size, as the grid measures it.
private struct IdealSizeBox: Layout {
    let size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(.unspecified) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

/// A path in the clipped view's own coordinates; nil clips nothing.
struct StagePath: Shape {
    var path: IslandPath?

    func path(in rect: CGRect) -> Path {
        guard let path else { return Path(rect.insetBy(dx: -1e5, dy: -1e5)) }
        return Path(path.cgPath)
    }
}

/// The view's own width, unbounded up and down: CSS `overflow-x: clip`. Inactive, it clips nothing.
struct AcrossClip: Shape {
    var active: Bool

    func path(in rect: CGRect) -> Path {
        let across = active ? rect.insetBy(dx: 0, dy: -1e5) : rect.insetBy(dx: -1e5, dy: -1e5)
        return Path(across)
    }
}
