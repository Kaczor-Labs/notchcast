import AppKit
import IslandCore
import IslandUI

@MainActor
final class IslandController: NSObject {
    private let source = IslandFrameSource()
    private let backdrop = IslandBackdrop()
    private let canvas = IslandCanvas()
    private var surface: IslandSurface<CGSize>?
    private var layout: IslandLayout?
    private weak var panel: PalettePanel?
    private var observer: PanelObserver?
    private let clip = CAShapeLayer()
    private var overlays: [CGRect] = []
    private(set) var samples: [String] = []
    private var captureName: String?
    private(set) var captured: [String] = []
    var showsRest = true
    var onOpen: (() -> Void)? {
        didSet { canvas.onOpen = onOpen }
    }

    override init() {
        super.init()
        backdrop.contentView = canvas
        canvas.wantsLayer = true
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.button)
        canvas.setAccessibilityLabel(NSRunningApplication.current.localizedName)
        source.didFrame = { [weak self] in self?.paintFrame() }
    }

    func attach(_ panel: PalettePanel, screen: NSScreen) {
        panel.level = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 1)
        guard self.panel !== panel else { return }
        self.panel = panel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.mask = clip
        panel.hasShadow = false
        observer = PanelObserver(panel: panel) { [weak self] in self?.frameChanged() }
        if layout == nil { configure(screen) }
        frameChanged()
    }

    func detach() {
        observer = nil
        if panel?.contentView?.layer?.mask === clip { panel?.contentView?.layer?.mask = nil }
        panel = nil
        closed()
    }

    func configure(_ screen: NSScreen) {
        let next = IslandLayout(screen: screen.frame, notch: Self.notch(on: screen))
        layout = next
        backdrop.setFrame(next.window, display: false)
        var metrics = IslandMetrics.standard
        metrics.screen = .init(width: next.canvas.width, height: next.canvas.height)
        metrics.top = next.top
        metrics.idle = .init(width: next.hasNotch ? next.notch.width : 96,
                             height: next.hasNotch ? next.notch.height * 2 : 24)
        metrics.corner.smoothing = 0
        metrics.expanded.top = next.top
        metrics.expanded.sideInset = 0
        metrics.expanded.padding = .init(top: next.contentTop * 2, side: 0, bottom: 0)
        metrics.expanded.rowGap = 0
        metrics.expanded.centerTop = 0
        metrics.expanded.minHeight = 24
        metrics.expanded.maxHeight = next.canvas.height
        metrics.expanded.radius = 26
        metrics.expanded.shadow.pull = .init(side: 0, top: 0, bottom: 0, opacity: 0)
        metrics.sensor.opacity = 0
        let surface = IslandSurface<CGSize>(
            presentation: .idle, clock: FrameClock(frameSource: source), metrics: metrics,
            motion: .standard, dpr: screen.backingScaleFactor, reduced: !Motion.isEnabled,
            keyline: 0, stageWidth: 750, measure: { presentation, _ in
                guard case .expanded(let content) = presentation else { return ContentMeasures() }
                return ContentMeasures(expandedHeight: Double(content.bottom?.height ?? 0))
            })
        self.surface = surface
        source.display.host = canvas
        if showsRest { backdrop.orderFrontRegardless() }
        paintFrame()
    }

    static func notch(on screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }

    @objc private func frameChanged() {
        guard let surface, let layout else { return }
        panel?.level = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 1)
        let palette = panel.flatMap { $0.isVisible ? $0.frame : nil }
        let overlay = IslandOverlayLayout(screen: layout.screen,
            contentTop: layout.screen.maxY - layout.contentTop, palette: palette).surface(overlays)
        let size = CGSize(width: max(palette?.width ?? 0, overlay?.width ?? 0),
                          height: max(palette?.height ?? 0, overlay?.height ?? 0))
        surface.batch {
            if size != .zero {
                backdrop.orderFrontRegardless()
                surface.resize(stageWidth: size.width, animate: true)
                surface.show(.expanded(.init(bottom: size)), contentKey: "palette")
            } else {
                surface.show(.idle, contentKey: "rest")
            }
        }
        paintFrame()
    }

    func opened() {
        backdrop.orderFrontRegardless()
        frameChanged()
    }

    func closed() {
        frameChanged()
    }

    func setOverlays(_ frames: [CGRect]) {
        overlays = frames
        frameChanged()
    }

    func capture(_ name: String) {
        captureName = name
        _ = source.requestFrame {}
    }

    private func paintFrame() {
        guard let layout, let surface else { return }
        let outline = surface.shape.paths.outline.cgPath
        var backgroundTransform = layout.stageTransform(width: surface.stageWidth)
        var contentTransform = panel.map {
            layout.maskTransform(width: surface.stageWidth, panel: $0.frame, flipped: $0.contentView?.isFlipped == true)
        } ?? backgroundTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.outline = outline.copy(using: &backgroundTransform)
        canvas.display()
        clip.path = outline.copy(using: &contentTransform)
        CATransaction.commit()
        CATransaction.flush()
        let bounds = outline.boundingBoxOfPath
        if !showsRest, overlays.isEmpty, panel?.isVisible != true,
           abs(bounds.width - (layout.hasNotch ? layout.notch.width : 96)) < 0.01 {
            backdrop.orderOut(nil)
        }
        if IslandVerification.enabled, let panel {
            let expected = canvas.outline?.boundingBoxOfPath.offsetBy(
                dx: backdrop.frame.minX, dy: backdrop.frame.minY) ?? .zero
            let local = clip.path?.boundingBoxOfPath ?? .zero
            let actual = CGRect(x: panel.frame.minX + local.minX,
                y: panel.contentView?.isFlipped == true ? panel.frame.maxY - local.maxY : panel.frame.minY + local.minY,
                width: local.width, height: local.height)
            let error = max(abs(expected.minX - actual.minX), abs(expected.minY - actual.minY),
                            abs(expected.maxX - actual.maxX), abs(expected.maxY - actual.maxY))
            samples.append("\(CACurrentMediaTime())\t\(panel.frame)\t\(backdrop.frame)\t\(expected)\t\(actual)\t\(error)")
            if let captureName {
                self.captureName = nil
                #if DEBUG
                IslandVerification.capture(captureName, backdrop: backdrop, panel: panel)
                captured.append(captureName)
                #endif
            }
        }
    }

    var frameIntervals: [Double] { source.intervals }
    var frameCPU: [Double] { source.cpuMilliseconds }

    isolated deinit {
        backdrop.orderOut(nil)
    }

    @MainActor
    private final class PanelObserver: NSObject {
        private let changed: () -> Void
        init(panel: NSWindow, changed: @escaping () -> Void) {
            self.changed = changed
            super.init()
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didBecomeKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: panel)
            }
        }
        @objc private func update() { changed() }
        isolated deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private final class IslandBackdrop: NSPanel {
    static let levelValue = Int(CGWindowLevelForKey(.mainMenuWindow)) + 1
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Self.levelValue)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class IslandCanvas: NSView {
    var outline: CGPath?
    var onOpen: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        outline?.contains(point) == true ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard outline?.contains(convert(event.locationInWindow, from: nil)) == true else { return }
        onOpen?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard let onOpen else { return false }
        onOpen()
        return true
    }
}
