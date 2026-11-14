import AppKit
import IslandCore
import SwiftUI

/// What the island's hit areas ask of the stack.
@MainActor
struct IslandHitActions {
    /// A left-button press began on `target`.
    var press: (PressTarget) -> Void
    /// The press ended; `cancel` when it left the target first.
    var release: (_ cancel: Bool) -> Void
    /// Enter, Space or an assistive press on `target`.
    var activate: (PressTarget) -> Void
    /// A press outside, or Escape, while expanded.
    var collapse: () -> Void
}

/// The pill and bubble hit areas over the stage, as buttons shaped like the island.
struct IslandHits: NSViewRepresentable {
    var shape: FrameGeometry
    var pillLabel: String?
    var bubbleLabel: String?
    var expanded: Bool
    var actions: IslandHitActions
    var frameSource: DisplayLinkFrameSource? = nil

    func makeNSView(context: Context) -> IslandHitLayer {
        IslandHitLayer()
    }

    func updateNSView(_ layer: IslandHitLayer, context: Context) {
        layer.apply(self, contentFocus: context.environment.islandContentFocus)
    }
}

/// Holds the two hit buttons; hits anywhere else fall through to what is under the island.
final class IslandHitLayer: NSView {
    let pill = IslandHitView(target: .pill)
    let bubble = IslandHitView(target: .bubble)
    private(set) var outline: CGPath?
    private(set) var expanded = false
    private(set) var contentFocus = ContentFocus.outside
    private var actions: IslandHitActions?
    private var monitors: [Any] = []
    private weak var frameSource: DisplayLinkFrameSource?
    private var clockRoot: DisplayLinkFrameSource.Root?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(pill)
        addSubview(bubble)
        bubble.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func apply(_ hits: IslandHits, contentFocus: ContentFocus) {
        if frameSource !== hits.frameSource {
            clockRoot?.removeFromSuperview()
            frameSource = hits.frameSource
            clockRoot = frameSource?.track(self)
        }
        actions = hits.actions
        let box = hits.shape.pill
        pill.place(x: box.x, y: box.y, width: box.width, height: box.height, radius: box.radius)
        pill.label = hits.pillLabel
        pill.expanded = hits.expanded
        pill.actions = hits.actions
        let bubbleBox = hits.shape.bubble
        bubble.label = hits.bubbleLabel
        bubble.expanded = hits.expanded
        bubble.actions = hits.actions
        bubble.isHidden = hits.bubbleLabel == nil || bubbleBox.height < 1
        bubble.place(
            x: bubbleBox.x, y: bubbleBox.y, width: bubbleBox.width, height: bubbleBox.height,
            radius: bubbleBox.height / 2)
        outline = hits.expanded && !hits.shape.paths.outline.isEmpty ? hits.shape.paths.outline.cgPath : nil
        if hits.expanded != expanded {
            expanded = hits.expanded
            updateMonitors()
        }
        self.contentFocus = contentFocus
        // surface.tsx: "Don't strand keyboard focus inside content that is going away."
        if contentFocus == .leaving, window?.firstResponder !== pill { focusPill(ring: true) }
    }

    /// Moves focus to the pill; one that takes none (no activity) leaves the window with it instead.
    private func focusPill(ring: Bool) {
        guard let window else { return }
        if !window.makeFirstResponder(pill) { window.makeFirstResponder(nil) }
        pill.showsRing = ring
    }

    override func draw(_ dirtyRect: NSRect) {
        for view in [pill, bubble] where view.ringShown {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.translateBy(x: view.frame.minX, y: view.frame.minY)
            context.addPath(view.ring)
            context.setStrokeColor(focusRing.color)
            context.setLineWidth(focusRing.width)
            context.strokePath()
            context.restoreGState()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // The expanded layer comes after the buttons, so it takes the press inside its outline.
        if let outline, outline.contains(local) { return nil }
        for view in [bubble, pill] where !view.isHidden && view.contains(convert(local, to: view)) {
            return view
        }
        return nil
    }

    /// Whether a press at `point` (in this view) lands on the island: a button or the expanded layer.
    func isInside(_ point: NSPoint) -> Bool {
        if let outline, outline.contains(point) { return true }
        return [pill, bubble].contains { !$0.isHidden && $0.contains(convert(point, to: $0)) }
    }

    private func updateMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        guard expanded, window != nil else { return }
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDownAnywhere(event) }
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.keyDownAnywhere(event) }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func mouseDownAnywhere(_ event: NSEvent) {
        guard expanded, let window, event.window === window else { return }
        if isInside(convert(event.locationInWindow, from: nil)) { return }
        let stranded = contentFocus != .outside
        actions?.collapse()
        if stranded { focusPill(ring: false) }
    }

    private func keyDownAnywhere(_ event: NSEvent) {
        guard expanded, let window, event.window === window, event.keyCode == escapeKey else { return }
        let focusInside = window.firstResponder === pill || window.firstResponder === bubble
        actions?.collapse()
        if focusInside { focusPill(ring: true) }
    }

    isolated deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}

private let escapeKey: UInt16 = 53
private let activationKeys: Set<UInt16> = [36, 76, 49]

/// surface.tsx `[data-islandcn-hit]:focus-visible{outline:2px solid #0a84ff;outline-offset:3px}`.
let focusRing = (width: 2.0, offset: 3.0, color: CGColor(srgbRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1))

/// One hit button: the pill's box or the bubble's, rounded as CSS rounds a `border-radius`.
final class IslandHitView: NSView {
    let target: PressTarget
    var actions: IslandHitActions?
    var label: String? {
        didSet { if label == nil, window?.firstResponder === self { window?.makeFirstResponder(nil) } }
    }
    var expanded = false
    /// As `:focus-visible`: a press hides the ring, keyboard use shows it again.
    var showsRing = false {
        didSet { if showsRing != oldValue { superview?.needsDisplay = true } }
    }
    private var radius = 0.0
    private var pressLocation: NSPoint?

    init(target: PressTarget) {
        self.target = target
        super.init(frame: .zero)
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override var isHidden: Bool {
        didSet { if isHidden != oldValue, showsRing { superview?.needsDisplay = true } }
    }

    func place(x: Double, y: Double, width: Double, height: Double, radius: Double) {
        let frame = NSRect(x: x, y: y, width: max(0, width), height: max(0, height))
        guard frame != self.frame || radius != self.radius else { return }
        self.frame = frame
        self.radius = radius
        cancelPressOutside()
        if ringShown { superview?.needsDisplay = true }
    }

    private var cornerRadius: Double { max(0, min(radius, bounds.width / 2, bounds.height / 2)) }

    /// The box with its corners capped at half its shorter side.
    var path: CGPath {
        CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    /// Whether the focus ring draws: focused, shown, and on screen.
    var ringShown: Bool { showsRing && !isHidden && window?.firstResponder === self }

    /// The ring's centre line: the box outset by the offset and half the width, its corners by as much.
    var ring: CGPath {
        let out = focusRing.offset + focusRing.width / 2
        let r = cornerRadius > 0 ? cornerRadius + out : 0
        return CGPath(roundedRect: bounds.insetBy(dx: -out, dy: -out), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    func contains(_ point: NSPoint) -> Bool {
        bounds.width > 0 && bounds.height > 0 && path.contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        showsRing = false
        pressLocation = event.locationInWindow
        actions?.press(target)
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressLocation != nil else { return }
        pressLocation = event.locationInWindow
        cancelPressOutside()
    }

    private func cancelPressOutside() {
        guard let pressLocation, !contains(convert(pressLocation, from: nil)) else { return }
        self.pressLocation = nil
        actions?.release(true)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressLocation != nil else { return }
        pressLocation = nil
        actions?.release(false)
    }

    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override var acceptsFirstResponder: Bool { label != nil }
    override var canBecomeKeyView: Bool { label != nil && !isHidden }

    override func becomeFirstResponder() -> Bool {
        showsRing = true
        superview?.needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        superview?.needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        showsRing = true
        guard activationKeys.contains(event.keyCode) else { return super.keyDown(with: event) }
        actions?.activate(target)
    }

    override func isAccessibilityElement() -> Bool { label != nil && !isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label }
    override func isAccessibilityExpanded() -> Bool { expanded }

    override func accessibilityPerformPress() -> Bool {
        guard label != nil else { return false }
        actions?.activate(target)
        return true
    }
}
