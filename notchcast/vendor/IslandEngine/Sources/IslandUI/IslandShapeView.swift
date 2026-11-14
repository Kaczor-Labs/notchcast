import AppKit
import IslandCore

/// The island's black shape, moving through its transitions.
///
/// The view is the stage: the shape sits at its top centre, laid out for the view's width up to a
/// phone's. `show` names the presentation and how big its content is; the view picks the
/// transition, springs from wherever the shape is now, and asks for frames only while it moves.
@MainActor
public final class IslandShapeView: NSView {
    public let metrics: IslandMetrics
    public let motion: IslandMotion
    public let clock: any IslandClock
    /// Whether changes ease instead of springing. Follows the system setting until set.
    public var reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// The shape as last drawn, in stage coordinates. nil until the first `show`.
    public private(set) var geometry: FrameGeometry?
    public private(set) var presentation: PresentationKind?
    public var isMoving: Bool { stopFrames != nil }

    private var animation: ShapeAnimation
    private var measure = ContentMeasure.empty
    private var target: ShapeTarget?
    private var shownWidth = 0.0
    private var stopFrames: Cancel?

    /// With no `clock` the view makes one that runs on its display's refresh.
    public init(metrics: IslandMetrics = .standard, motion: IslandMotion = .standard, clock: (any IslandClock)? = nil) {
        self.metrics = metrics
        self.motion = motion
        let source = DisplayLinkFrameSource()
        self.clock = clock ?? FrameClock(frameSource: source)
        let idle = ShapeTarget(.idle, measure: .empty, screenWidth: metrics.screen.width, metrics: metrics)
        animation = ShapeAnimation(target: idle, metrics: metrics)
        super.init(frame: NSRect(x: 0, y: 0, width: metrics.screen.width, height: 0))
        source.host = self
    }

    public required init?(coder: NSCoder) {
        fatalError("IslandShapeView is made in code")
    }

    isolated deinit {
        stopFrames?()
    }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    /// The width the island lays out against: this view's, but never wider than a phone.
    public var layoutWidth: Double { islandScreenWidth(containerWidth: bounds.width, metrics: metrics) }

    /// Moves to `kind` with content of size `measure`. `swap` says a different activity takes over.
    /// A call that changes nothing does nothing; the first call, and a call after the view's width
    /// changed, snap.
    public func show(_ kind: PresentationKind, measure: ContentMeasure = .empty, swap: Bool = false) {
        let width = layoutWidth
        let next = ShapeTarget(kind, measure: measure, screenWidth: width, metrics: metrics)
        let first = target == nil
        let instant = first || shownWidth != width
        let keyChanged = first || kind != presentation || swap
        if !keyChanged && !instant && next == target { return }
        let mode: MotionMode = instant ? .instant : reducesMotion ? .reduced : .spring
        let transition = ShapeTransition(
            from: presentation ?? kind, to: kind, swap: swap, swelling: false, alert: false)
        let now = clock.now()
        // A resize that lands on the same numbers keeps the motion under way.
        let sameShape = transition == .resize && mode == .spring && next == target
        if (keyChanged && !sameShape) || next != target || instant {
            let idle = ShapeTarget(.idle, measure: .empty, screenWidth: width, metrics: metrics)
            animation.retarget(
                ShapeChange(transition: transition, target: next, idle: idle, t0: now / 1000, motion: motion, mode: mode))
        }
        presentation = kind
        self.measure = measure
        target = next
        shownWidth = width
        redraw(at: now)
        run()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let presentation, layoutWidth != shownWidth { show(presentation, measure: measure) }
    }

    /// Paints the shape as last drawn into `context`, which is in this view's flipped coordinates.
    public func paint(in context: CGContext) {
        guard let geometry else { return }
        context.saveGState()
        context.translateBy(x: (bounds.width - layoutWidth) / 2, y: 0)
        paintShape(geometry, in: context)
        context.restoreGState()
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        paint(in: context)
    }

    private func redraw(at ms: Double) {
        geometry = animation.frame(at: ms / 1000, stageWidth: layoutWidth, metrics: metrics)
        needsDisplay = true
    }

    private func run() {
        if stopFrames != nil { return }
        stopFrames = clock.onFrame { [weak self] ms in self?.tick(ms) }
    }

    private func tick(_ ms: Double) {
        redraw(at: ms)
        if animation.isAtRest(at: ms / 1000) {
            // The draw above read the springs a step before they snapped to their targets.
            redraw(at: ms)
            stopFrames?()
            stopFrames = nil
        }
    }
}
