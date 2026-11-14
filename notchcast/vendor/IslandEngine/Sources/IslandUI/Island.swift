import IslandCore
import SwiftUI

/// Where an island draws: the top centre of the view it is placed in, or of the whole window.
public enum IslandPlacement: String, Sendable, CaseIterable {
    case container
    case viewport
}

/// Draws the activity stack of the nearest `islandModel(_:)`.
///
/// The island takes no height of its own and overflows downwards, so place it at the top of the
/// view it should sit in, usually as `.overlay(alignment: .top) { Island { … } }`.
public struct Island<Content, Slot: View>: View {
    @Environment(IslandModel<Content>.self) private var model: IslandModel<Content>?
    @Environment(\.islandReducedMotion) private var reduced
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandAnnouncer) private var announcer
    @State private var width: Double?
    @State private var built: Built<Content>?
    @State private var slotRef = SlotRef<Content, Slot>()

    let placement: IslandPlacement
    let label: String
    let keyline: KeylineSetting
    let backdrop: String?
    let slot: @MainActor (Content) -> Slot

    /// An island named `label` for assistive tech. `keyline` draws the thin band that separates the
    /// island from a dark page; `backdrop` is that page's colour (hex or `rgb()`), which sets its
    /// strength. `slot` draws one slot's content.
    public init(
        placement: IslandPlacement = .container, label: String = "Live activities", keyline: KeylineSetting = .auto,
        backdrop: String? = nil, @ViewBuilder slot: @escaping @MainActor (Content) -> Slot
    ) {
        self.placement = placement
        self.label = label
        self.keyline = keyline
        self.backdrop = backdrop
        self.slot = slot
    }

    public var body: some View {
        let model = requireModel()
        let scene = deriveScene(model.snapshot)
        let config = Config(
            model: ObjectIdentifier(model), metrics: model.metrics, motion: model.motion, dpr: displayScale)
        let alpha = keylineAlpha(keyline, backdrop: backdrop, metrics: model.metrics, darkMode: colorScheme == .dark)
        let _ = slotRef.slots = IslandSlots(metrics: model.metrics, view: slot)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .onGeometryChange(for: Double.self, of: { $0.size.width }, action: { width = $0 })
            .overlay(alignment: .top) {
                if let surface = built?.surface, built?.config == config {
                    IslandLiveSurface(
                        model: model, surface: surface,
                        slots: slotRef.slots ?? IslandSlots(metrics: model.metrics, view: slot))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(label)
                }
            }
            .modifier(Placement(placement: placement))
            .onChange(of: Rebuild(config: config, width: width), initial: true) { _, rebuild in
                guard let width = rebuild.width else { return }
                if let built, built.config == config {
                    built.surface.resize(stageWidth: width)
                    return
                }
                built = Built(surface: makeSurface(model, width: width, keyline: alpha), config: config)
            }
            .onChange(of: alpha) { _, alpha in built?.surface.keyline = alpha }
            .onChange(of: reduced) { _, reduced in built?.surface.reduced = reduced }
            .onChange(of: scene.label.islandIdentity) {
                if !scene.label.isEmpty { announcer.post(scene.label) }
            }
    }

    private func requireModel() -> IslandModel<Content> {
        guard let model else { preconditionFailure("islandcn: Island must be inside islandModel(_:).") }
        return model
    }

    private func makeSurface(_ model: IslandModel<Content>, width: Double, keyline: Double) -> IslandSurface<Content> {
        let ref = slotRef
        let metrics = model.metrics
        let view = slot
        let surface = IslandSurface(
            store: model.store, clock: model.clock, metrics: metrics, motion: model.motion, dpr: displayScale,
            reduced: reduced, keyline: keyline, stageWidth: width,
            measure: { presentation, width in
                (ref.slots ?? IslandSlots(metrics: metrics, view: view)).measure(presentation, stageWidth: width)
            })
        surface.recorder = model.recorder
        return surface
    }
}

extension Island where Content == AnyView, Slot == AnyView {
    /// An island whose activities carry their slot views as `AnyView`.
    public init(
        placement: IslandPlacement = .container, label: String = "Live activities", keyline: KeylineSetting = .auto,
        backdrop: String? = nil
    ) {
        self.init(placement: placement, label: label, keyline: keyline, backdrop: backdrop) { $0 }
    }
}

/// What the surface is built with; a change builds a new one.
private struct Config: Equatable {
    var model: ObjectIdentifier
    var metrics: IslandMetrics
    var motion: IslandMotion
    var dpr: Double
}

private struct Rebuild: Equatable {
    var config: Config
    var width: Double?
}

@MainActor
private struct Built<Content> {
    var surface: IslandSurface<Content>
    var config: Config
}

/// Keeps the newest slot closure where the surface's measure can reach it.
@MainActor
final class SlotRef<Content, Slot: View> {
    var slots: IslandSlots<Content, Slot>?
}

/// `viewport` runs under the window's title bar and safe areas, as `position: fixed` does.
struct Placement: ViewModifier {
    var placement: IslandPlacement

    func body(content: Content) -> some View {
        if placement == .viewport {
            content.modifier(ViewportPlacement()).ignoresSafeArea()
        } else {
            content
        }
    }
}
