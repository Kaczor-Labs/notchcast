#if DEBUG
import AppKit
import QuartzCore

final class IslandFrameTrace {
    var frames: [IslandController.FrameTrace] = []
    var onFrame: (() -> Void)?
}

extension IslandController {
    struct FrameTrace {
        let time: Double
        let bounds: CGRect
        let keylineAlpha: Double
        let keylineBounds: CGRect
    }

    /// Every painted frame, panel or not, so a scene reads an opening that has no launcher under it.
    var trace: [FrameTrace] { frames.frames }
    var onFrame: (() -> Void)? {
        get { frames.onFrame }
        set { frames.onFrame = newValue }
    }
    var headline: IslandHeadlineArt? { canvas.headline }
    var keylineLayer: CAShapeLayer { keyline }
    var contentMask: CALayer? { panel?.contentView?.layer?.mask }

    /// A notch for screens that have none, so the notch profile runs on the test display.
    static var simulatedNotch: CGSize?
    var shownStatuses: [String] { (canvas.glance as? IslandStatusArt)?.shown ?? [] }
    var noticeTone: NSColor? { (canvas.glance as? IslandNoticeArt)?.tone ?? canvas.headline?.tone }
    var showsHeadline: Bool { canvas.headline != nil }
    var reduced: Bool { surface?.reduced == true }
    var backdropVisible: Bool { backdrop.isVisible }
    var frameIntervals: [Double] { source.intervals }
    var frameCPU: [Double] { source.cpuMilliseconds }

    var backdropWindow: NSWindow { backdrop }
    var outlineBounds: CGRect { canvas.outline?.boundingBoxOfPath ?? .zero }
    var surfaceIdentity: ObjectIdentifier? { surface.map(ObjectIdentifier.init) }
    var contentKey: String? { surface?.contentKey }
    var overlayCount: Int { overlays.count }
    var acceptsClicks: Bool { canvas.canOpen?() == true }
    func pressBackdrop() -> Bool { canvas.accessibilityPerformPress() }
    /// Routes a synthetic click through the island window, so hit testing runs as for a real one.
    func clickBackdrop(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) {
        let bounds = outlineBounds
        let point = CGPoint(x: bounds.midX, y: (bounds.minY + min(bounds.maxY, canvas.bounds.height)) / 2)
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: backdrop.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        backdrop.sendEvent(event)
    }
    var pillFrame: CGRect? { pillRect }
    var glanceWidthTarget: Double { canvas.glance.map { glanceWidth($0.layout) } ?? 0 }
    var showsGlanceTitle: Bool { canvas.glance?.layout.showsTitle == true }

    func recordFrame() {
        guard IslandVerification.enabled else { return }
        frames.frames.append(FrameTrace(
            time: CACurrentMediaTime(), bounds: outlineBounds,
            keylineAlpha: Double(keyline.strokeColor?.alpha ?? 0),
            keylineBounds: keyline.path?.boundingBoxOfPath ?? .zero))
        frames.onFrame?()
    }
}
#endif
