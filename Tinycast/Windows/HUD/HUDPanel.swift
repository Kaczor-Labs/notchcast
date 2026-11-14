import AppKit

/// Borderless panel for a transient readout: never key, always above the palette.
final class HUDPanel: NSPanel {
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        AppCore.shared.island.overlays.dismissed(self)
    }

    init(acceptsMouseEvents: Bool = false) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        // Both HUDs take the palette's surface recipe, so neither carries elevation.
        hasShadow = true
        level = .palette
        ignoresMouseEvents = !acceptsMouseEvents
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
