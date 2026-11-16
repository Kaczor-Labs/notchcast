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
