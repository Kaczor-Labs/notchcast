import IslandCore
import SwiftUI

/// One presentation, controlled, without the activity stack: for docs, playgrounds and captures.
/// It draws the same shape and motion as `Island` but is not pressable. It works with or without
/// a model in the environment.
public struct IslandView<Content, Slot: View>: View {
    @Environment(\.islandContext) private var context
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandAnnouncer) private var announcer
    @State private var slotRef = SlotRef<Content, Slot>()
    @State private var width: Double?
    @State private var built: (surface: IslandSurface<Content>, config: ViewConfig)?

    let presentation: IslandPresentation<Content>
    let contentKey: String?
    let pressed: Bool
    let placement: IslandPlacement
    let label: String
    let liveLabel: String
    let clock: (any IslandClock)?
    let metrics: IslandMetrics?
    let motion: IslandMotion?
    let reducedMotion: ReducedMotionSetting?
    let keyline: KeylineSetting
    let backdrop: String?
    let slot: @MainActor (Content) -> Slot
    private let renderID = UUID()

    /// - Parameters:
    ///   - presentation: What to show. Changing it animates the shape and crossfades the content.
    ///   - contentKey: A new key crossfades, the same key updates in place; nil is the kind.
    ///   - pressed: Holds the pill down, so it squishes slightly.
    ///   - liveLabel: Announced politely when it changes.
    ///   - clock: nil is the model's clock, or the shared display clock.
    ///   - metrics: nil is the model's metrics, or the table's.
    ///   - motion: nil is the model's motion, or the table's.
    ///   - reducedMotion: nil is the model's setting, or `.user`.
    public init(
        presentation: IslandPresentation<Content>, contentKey: String? = nil, pressed: Bool = false,
        placement: IslandPlacement = .container, label: String = "Live activity", liveLabel: String = "",
        clock: (any IslandClock)? = nil, metrics: IslandMetrics? = nil, motion: IslandMotion? = nil,
        reducedMotion: ReducedMotionSetting? = nil, keyline: KeylineSetting = .auto, backdrop: String? = nil,
        @ViewBuilder slot: @escaping @MainActor (Content) -> Slot
    ) {
        self.presentation = presentation
        self.contentKey = contentKey
        self.pressed = pressed
        self.placement = placement
        self.label = label
        self.liveLabel = liveLabel
        self.clock = clock
        self.metrics = metrics
        self.motion = motion
        self.reducedMotion = reducedMotion
        self.keyline = keyline
        self.backdrop = backdrop
        self.slot = slot
    }

    public var body: some View {
        let metrics = metrics ?? context?.metrics ?? .standard
        let motion = motion ?? context?.motion ?? .standard
        let clock = clock ?? context?.clock ?? defaultClock()
        let reduced = (reducedMotion ?? context?.reducedMotion ?? .user).resolved(system: systemReduced)
        let alpha = keylineAlpha(keyline, backdrop: backdrop, metrics: metrics, darkMode: colorScheme == .dark)
        let config = ViewConfig(clock: ObjectIdentifier(clock), metrics: metrics, motion: motion, dpr: displayScale)
        let _ = slotRef.slots = IslandSlots(metrics: metrics, view: slot)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .onGeometryChange(for: Double.self, of: { $0.size.width }, action: { width = $0 })
            .overlay(alignment: .top) {
                if let built, built.config == config {
                    IslandSurfaceView(surface: built.surface, slots: IslandSlots(metrics: metrics, view: slot))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(label)
                }
            }
            .modifier(Placement(placement: placement))
            .onChange(of: ViewRebuild(config: config, width: width), initial: true) { _, rebuild in
                guard let width = rebuild.width else { return }
                if let built, built.config == config {
                    built.surface.resize(stageWidth: width)
                    return
                }
                let slots = IslandSlots(metrics: metrics, view: slot)
                let surface = IslandSurface(
                    presentation: presentation, contentKey: contentKey, pressed: pressed, clock: clock,
                    metrics: metrics, motion: motion, dpr: displayScale, reduced: reduced, keyline: alpha,
                    stageWidth: width, measure: { (slotRef.slots ?? slots).measure($0, stageWidth: $1) })
                surface.recorder = context?.recorder
                built = (surface, config)
            }
            .onChange(of: renderID) {
                built?.surface.show(presentation, contentKey: contentKey, pressed: pressed)
            }
            .onChange(of: alpha) { _, alpha in built?.surface.keyline = alpha }
            .onChange(of: reduced) { _, reduced in built?.surface.reduced = reduced }
            .onChange(of: liveLabel.islandIdentity) {
                if !liveLabel.isEmpty { announcer.post(liveLabel) }
            }
    }
}

/// What a controlled surface is built with; a change builds a new one.
private struct ViewConfig: Equatable {
    var clock: ObjectIdentifier
    var metrics: IslandMetrics
    var motion: IslandMotion
    var dpr: Double
}

private struct ViewRebuild: Equatable {
    var config: ViewConfig
    var width: Double?
}
