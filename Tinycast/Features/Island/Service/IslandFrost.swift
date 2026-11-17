import AppKit

/// Frosted's material: a behind-window blur cut to the outline, and a lift beneath it.
@MainActor
final class IslandFrost {
    /// The backdrop's content: the blur, then the canvas with the tint, the edge and the art.
    let root: NSView
    private let clip = IslandInertView()
    private let blur = IslandBlurView()
    private let mask = CAShapeLayer()
    private let lift = IslandLiftWindow()
    private var liftShape: (CGPath, NotchTheme.Shadow)?

    init(canvas: NSView) {
        root = IslandFrostRoot()
        root.wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.mask = mask
        clip.isHidden = true
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        for view in [clip, blur, canvas] { view.autoresizingMask = [.width, .height] }
        clip.addSubview(blur)
        root.addSubview(clip)
        root.addSubview(canvas)
    }

    var sharingType: NSWindow.SharingType {
        get { lift.sharingType }
        set { lift.sharingType = newValue }
    }

    #if DEBUG
    var liftShown: Bool { lift.isVisible && lift.parent != nil && lift.casting }
    var liftClickThrough: Bool { lift.ignoresMouseEvents }
    #endif

    /// Called inside the frame's transaction; the lift follows only a settled outline (`settled`).
    func paint(look: IslandLook, solid: Bool, outline: CGPath?, shadow: NotchTheme.Shadow?, settled: Bool,
               backdrop: NSWindow, reducedMotion: Bool) {
        guard look == .frosted else {
            clip.isHidden = true
            liftShape = nil
            if lift.parent != nil { backdrop.removeChildWindow(lift); lift.orderOut(nil) }
            return
        }
        clip.isHidden = solid
        mask.path = outline
        if lift.frame != backdrop.frame { lift.setFrame(backdrop.frame, display: false) }
        if lift.parent == nil, backdrop.isVisible { backdrop.addChildWindow(lift, ordered: .below) }
        guard settled, let outline, let shadow else {
            if liftShape != nil { liftShape = nil; lift.show(nil, animated: false) }
            return
        }
        if let liftShape, liftShape.0 == outline, liftShape.1 == shadow { return }
        liftShape = (outline, shadow)
        lift.show((outline, shadow), animated: !reducedMotion)
    }
}

private final class IslandFrostRoot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

private final class IslandInertView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class IslandBlurView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The shadow lives in its own click-through window, so its halo never swallows a click below it.
private final class IslandLiftWindow: NSPanel {
    private let caster = CALayer()
    private let cutout = CAShapeLayer()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: IslandBackdrop.levelValue)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        contentView = view
        caster.shadowColor = NSColor.black.cgColor
        caster.opacity = 0
        cutout.fillRule = .evenOdd
        caster.mask = cutout
        view.layer?.addSublayer(caster)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    #if DEBUG
    var casting: Bool { caster.opacity > 0 }
    #endif

    /// Cut out under the glass, so the shadow never darkens the blur.
    func show(_ shape: (CGPath, NotchTheme.Shadow)?, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || shape == nil)
        CATransaction.setAnimationDuration(Theme.Duration.dialogEnter)
        if let (outline, shadow) = shape {
            let bounds = contentView?.bounds ?? .zero
            caster.frame = bounds
            caster.shadowPath = Self.spread(outline, by: shadow.spread)
            caster.shadowOffset = CGSize(width: 0, height: -shadow.y)
            caster.shadowRadius = shadow.blur / 2
            caster.shadowOpacity = shadow.opacity
            let cut = CGMutablePath()
            cut.addRect(bounds)
            cut.addPath(outline)
            cutout.frame = bounds
            cutout.path = cut
            caster.opacity = 1
        } else {
            caster.opacity = 0
        }
        CATransaction.commit()
    }

    /// CSS spread on any engine shape: the outline scaled about its centre by the spread.
    private static func spread(_ outline: CGPath, by amount: CGFloat) -> CGPath {
        let box = outline.boundingBoxOfPath
        guard box.width > -2 * amount, box.height > -2 * amount else { return outline }
        var transform = CGAffineTransform(translationX: box.midX, y: box.midY)
            .scaledBy(x: (box.width + 2 * amount) / box.width, y: (box.height + 2 * amount) / box.height)
            .translatedBy(x: -box.midX, y: -box.midY)
        return outline.copy(using: &transform) ?? outline
    }
}
