import IslandCore
import SwiftUI

/// A surface drawn with its hit areas wired to `model`: presses, releases, activation and collapse.
@_spi(Lab)
public struct IslandLiveSurface<Content, Slot: View>: View {
    let model: IslandModel<Content>
    let surface: IslandSurface<Content>
    let slots: IslandSlots<Content, Slot>

    public init(model: IslandModel<Content>, surface: IslandSurface<Content>, slots: IslandSlots<Content, Slot>) {
        self.model = model
        self.surface = surface
        self.slots = slots
    }

    public var body: some View {
        let scene = deriveScene(model.snapshot)
        let expanded = scene.presentation.kind == .expanded
        IslandSurfaceView(
            surface: surface, slots: slots,
            hits: AnyView(
                IslandHits(
                    shape: surface.shape, pillLabel: pillLabel(scene, expanded: expanded),
                    bubbleLabel: scene.detached.map { "\($0.label). Press to expand." },
                    expanded: expanded, actions: actions(scene: scene, expanded: expanded), frameSource: model.frameSource)))
    }

    /// The pill's name: none without an activity, when the pill still swells but is not a control.
    private func pillLabel(_ scene: IslandScene<Content>, expanded: Bool) -> String? {
        guard let primary = scene.primary?.label else { return nil }
        return expanded ? "\(primary), expanded. Press Escape to collapse." : "\(primary). Press to expand."
    }

    private func actions(scene: IslandScene<Content>, expanded: Bool) -> IslandHitActions {
        let model = model
        return IslandHitActions(
            press: { model.press($0) },
            release: { model.release(cancel: $0) },
            activate: { target in
                if expanded { return model.collapse() }
                let activity = target == .bubble ? scene.detached : scene.primary
                if let activity { model.expand(activity.id) }
            },
            collapse: { model.collapse() })
    }
}
