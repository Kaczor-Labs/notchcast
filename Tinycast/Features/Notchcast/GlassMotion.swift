import AppKit

/// How a glass surface (menu, HUD, dialog) arrives and leaves: a fade and a short slide, never a scale.
extension NSWindow {
    private static let glassSlideKey = "glassSlide"
    /// Windows a leave made deaf to clicks, so a HUD that never took any stays that way.
    private static let glassMuted = NSHashTable<NSWindow>.weakObjects()

    /// `rising` is a menu that opens upward from its control; every other surface comes down from the island.
    func glassEnter(rising: Bool = false, order: () -> Void) {
        animationBehavior = .none
        glassHear()
        alphaValue = 0
        order()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(NotchTheme.GlassLayer.enter)
            context.timingFunction = Self.glassTiming(NotchTheme.GlassLayer.landing)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // The shadow is cached from the first frame drawn, so it is redrawn once the surface has landed.
            MainActor.assumeIsolated { self?.invalidateShadow() }
        }
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
        // A surface on its way out is gone to the user: no second click, no keys, no hold on the island.
        if !ignoresMouseEvents {
            ignoresMouseEvents = true
            Self.glassMuted.add(self)
        }
        if isKeyWindow { glassNextKey?.makeKey() }
        AppCore.shared.island.overlays.setLeaving(self, true)
        glassSlide(entering: false, rising: rising)
        // The strong capture keeps a window nobody else holds alive until it has faded.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchTheme.GlassLayer.leave
            context.timingFunction = Self.glassTiming(NotchTheme.GlassLayer.leaving)
            animator().alphaValue = 0
        } completionHandler: { [self] in
            MainActor.assumeIsolated {
                // Called back mid-fade, it is opaque again and stays.
                guard alphaValue == 0 else { return }
                orderOut(nil)
                done?()
            }
        }
    }

    /// A surface called back while it leaves stays where it is.
    func glassStay() {
        contentView?.layer?.removeAnimation(forKey: Self.glassSlideKey)
        cancelFade()
        glassHear()
        AppCore.shared.island.overlays.setLeaving(self, false)
    }

    /// The frontmost other window that takes keys, as `orderOut` would pick; `orderedWindows` lists no panel.
    private var glassNextKey: NSWindow? {
        NSWindow.windowNumbers(options: [])?.lazy.compactMap { NSApp.window(withWindowNumber: $0.intValue) }
            .first { $0 !== self && $0.canBecomeKey }
    }

    private func glassHear() {
        guard Self.glassMuted.contains(self) else { return }
        Self.glassMuted.remove(self)
        ignoresMouseEvents = false
    }

    private static func glassTiming(_ curve: (x1: Double, y1: Double, x2: Double, y2: Double)) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2))
    }

    private func glassSlide(entering: Bool, rising: Bool) {
        contentView?.wantsLayer = true
        contentView?.layer?.removeAnimation(forKey: Self.glassSlideKey)
        guard Motion.isEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = contentView?.layer else { return }
        // The offset is in the superlayer's space, which AppKit may flip: ask it which way is up.
        let up: CGFloat = layer.superlayer?.contentsAreFlipped() == true ? -1 : 1
        let offset = (rising ? -up : up) * NotchTheme.GlassLayer.slide
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = entering ? offset : 0
        slide.toValue = entering ? 0 : offset
        slide.duration = entering ? NotchTheme.GlassLayer.enter : NotchTheme.GlassLayer.leave
        slide.timingFunction = Self.glassTiming(entering ? NotchTheme.GlassLayer.landing : NotchTheme.GlassLayer.leaving)
        layer.add(slide, forKey: Self.glassSlideKey)
    }
}

extension MenuPanelCorner {
    /// True when the menu landed above its control (a footer menu, or one flipped for lack of room below).
    func rises(placed: CGRect, parent: CGRect) -> Bool {
        switch self {
        case .bottomLeading, .bottomTrailing: true
        case .belowHeaderTrailing: false
        case .belowControl(let control, _): placed.minY >= parent.maxY - control.minY
        }
    }
}
