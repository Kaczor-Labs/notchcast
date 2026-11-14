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
    #if DEBUG
    private(set) var samples: [String] = []
    private var captureName: String?
    private(set) var captured: [String] = []
    #endif
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
        canvas.canOpen = { [weak self] in
            guard let self else { return false }
            return self.panel?.isVisible != true && self.overlays.isEmpty && NSApp.modalWindow == nil && self.isResting
        }
        source.didFrame = { [weak self] in self?.paintFrame() }
    }

    func attach(_ panel: PalettePanel, screen: NSScreen) {
        guard self.panel !== panel else { return }
        if !panel.isVisible, NSApp.modalWindow == nil { panel.level = Self.paletteLevel }
        self.panel = panel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.mask = clip
        panel.hasShadow = false
        observer = PanelObserver(panel: panel, changed: { [weak self] in self?.frameChanged() },
            becameKey: { [weak self] in self?.restoreLevel() })
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
        let next = IslandLayout(screen: screen.frame, notch: Self.notch(on: screen), canvas: Theme.Size.islandHost)
        layout = next
        backdrop.setFrame(next.window, display: false)
        if surface != nil {
            if showsRest, panel?.isVisible != true, NSApp.modalWindow == nil { backdrop.orderFrontRegardless() }
            frameChanged()
            return
        }
        var metrics = IslandMetrics.standard
        metrics.screen = .init(width: next.canvas.width, height: next.canvas.height)
        metrics.top = next.top
        metrics.idle = .init(width: next.hasNotch ? next.notch.width : Theme.Size.islandRest.width,
                             height: next.hasNotch ? next.notch.height * 2 : Theme.Size.islandRest.height)
        metrics.corner.smoothing = 0
        metrics.expanded.top = next.top
        metrics.expanded.sideInset = 0
        metrics.expanded.padding = .init(top: next.contentTop * 2, side: 0, bottom: 0)
        metrics.expanded.rowGap = 0
        metrics.expanded.centerTop = 0
        metrics.expanded.minHeight = Theme.Size.islandRest.height
        metrics.expanded.maxHeight = next.canvas.height
        metrics.expanded.radius = Theme.Radius.panel
        metrics.expanded.shadow.pull = .init(side: 0, top: 0, bottom: 0, opacity: 0)
        metrics.sensor.opacity = 0
        let surface = IslandSurface<CGSize>(
            presentation: .idle, clock: FrameClock(frameSource: source), metrics: metrics,
            motion: .standard, dpr: screen.backingScaleFactor, reduced: !Motion.isEnabled,
            keyline: 0, stageWidth: Theme.Size.panelWidth, measure: { presentation, _ in
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
        let suspended = panel.map { $0.isVisible && ($0.level < Self.paletteLevel || NSApp.modalWindow != nil) } ?? false
        if suspended { backdrop.orderOut(nil) }
        let palette = panel.flatMap { $0.isVisible ? $0.frame : nil }
        let overlay = IslandOverlayLayout(screen: layout.screen,
            contentTop: layout.screen.maxY - layout.contentTop, palette: palette,
            inset: Theme.Spacing.islandInset, gap: Theme.Spacing.xl).surface(overlays)
        let size = CGSize(width: max(palette?.width ?? 0, overlay?.width ?? 0),
                          height: max(palette?.height ?? 0, overlay?.height ?? 0))
        surface.batch {
            if size != .zero {
                if !suspended { backdrop.orderFrontRegardless() }
                surface.resize(stageWidth: size.width, animate: true)
                surface.show(.expanded(.init(bottom: size)), contentKey: "palette")
            } else {
                surface.show(.idle, contentKey: "rest")
            }
        }
        paintFrame()
    }

    func opened() {
        frameChanged()
    }

    private static var paletteLevel: NSWindow.Level { NSWindow.Level(rawValue: IslandBackdrop.levelValue + 1) }

    private var isResting: Bool {
        guard let layout, let bounds = canvas.outline?.boundingBoxOfPath else { return false }
        let size = layout.hasNotch ? CGSize(width: layout.notch.width, height: layout.notch.height * 2) : Theme.Size.islandRest
        return abs(bounds.width - size.width) < 0.01 && abs(bounds.height - size.height) < 0.01
    }

    private func restoreLevel() {
        guard let panel, let layout, panel.isKeyWindow, NSApp.modalWindow == nil else { return }
        panel.level = Self.paletteLevel
        panel.setFrameOrigin(CGPoint(x: layout.screen.midX - panel.frame.width / 2,
                                     y: layout.screen.maxY - layout.contentTop - panel.frame.height))
        frameChanged()
    }

    func closed() {
        frameChanged()
    }

    func setOverlays(_ frames: [CGRect]) {
        overlays = frames
        frameChanged()
    }

    #if DEBUG
    func capture(_ name: String) {
        captureName = name
        _ = source.requestFrame {}
    }
    #endif

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
           abs(bounds.width - (layout.hasNotch ? layout.notch.width : Theme.Size.islandRest.width)) < 0.01 {
            backdrop.orderOut(nil)
        }
        #if DEBUG
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
                IslandVerification.capture(captureName, backdrop: backdrop, panel: panel)
                captured.append(captureName)
            }
        }
        #endif
    }

    #if DEBUG
    var frameIntervals: [Double] { source.intervals }
    var frameCPU: [Double] { source.cpuMilliseconds }

    var backdropWindow: NSWindow { backdrop }
    var outlineBounds: CGRect { canvas.outline?.boundingBoxOfPath ?? .zero }
    var overlayCount: Int { overlays.count }
    func pressBackdrop() -> Bool { canvas.accessibilityPerformPress() }
    #endif

    isolated deinit {
        backdrop.orderOut(nil)
    }

    @MainActor
    private final class PanelObserver: NSObject {
        private let changed: () -> Void
        private let becameKey: () -> Void
        private var level: NSKeyValueObservation?
        init(panel: NSWindow, changed: @escaping () -> Void, becameKey: @escaping () -> Void) {
            self.changed = changed
            self.becameKey = becameKey
            super.init()
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: panel)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged),
                name: NSWindow.didBecomeKeyNotification, object: panel)
            level = panel.observe(\.level) { [weak self] _, _ in
                guard let self else { return }
                RunLoop.main.perform(#selector(update), target: self, argument: nil, order: 0, modes: [.common])
            }
        }
        @objc private func update() { changed() }
        @objc private func keyChanged() {
            Task { @MainActor [weak self] in self?.becameKey() }
        }
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
        hidesOnDeactivate = false
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
    var canOpen: (() -> Bool)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setFillColor(NSColor(Theme.Colors.islandSurface).cgColor)
        context.fillPath()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        outline?.contains(point) == true ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard canOpen?() == true, outline?.contains(convert(event.locationInWindow, from: nil)) == true else { return }
        onOpen?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard canOpen?() == true, let onOpen else { return false }
        onOpen()
        return true
    }
}
