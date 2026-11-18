import AppKit

/// How a glass surface (menu, HUD, dialog) arrives and leaves: a fade and a short slide, never a scale.
extension NSWindow {
    private static let glassSlideKey = "glassSlide"

    /// `rising` is a menu that opens upward from the footer; every other surface comes down from the island.
    func glassEnter(rising: Bool = false, order: () -> Void) {
        animationBehavior = .none
        fadeIn(duration: NotchTheme.GlassLayer.enter, order: order)
        glassSlide(entering: true, rising: rising)
    }

    /// `done` runs once the window is off screen; with motion off that is before this returns.
    func glassLeave(rising: Bool = false, done: (@MainActor () -> Void)? = nil) {
        animationBehavior = .none
        guard Motion.isEnabled, isVisible else {
            orderOut(nil)
            done?()
            return
        }
        glassSlide(entering: false, rising: rising)
        // The strong capture keeps a window nobody else holds alive until it has faded.
        fadeOut(duration: NotchTheme.GlassLayer.leave) { [self] in
            _ = self
            done?()
        }
    }

    /// A surface called back while it leaves stays where it is.
    func glassStay() {
        contentView?.layer?.removeAnimation(forKey: Self.glassSlideKey)
        cancelFade()
    }

    private func glassSlide(entering: Bool, rising: Bool) {
        contentView?.wantsLayer = true
        contentView?.layer?.removeAnimation(forKey: Self.glassSlideKey)
        guard Motion.isEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = contentView?.layer else { return }
        // Layer space is y-up: positive starts above the resting place.
        let offset = rising ? -NotchTheme.GlassLayer.slide : NotchTheme.GlassLayer.slide
        let curve = entering ? NotchTheme.GlassLayer.landing : NotchTheme.GlassLayer.leaving
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = entering ? offset : 0
        slide.toValue = entering ? 0 : offset
        slide.duration = entering ? NotchTheme.GlassLayer.enter : NotchTheme.GlassLayer.leave
        slide.timingFunction = CAMediaTimingFunction(
            controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2))
        layer.add(slide, forKey: Self.glassSlideKey)
    }
}
