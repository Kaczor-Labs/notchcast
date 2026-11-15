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
    private var configuration: IslandSurfaceConfiguration?
    private var pendingScreen: NSScreen?
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
    var canOpen: (() -> Bool)?
    var onOpen: (() -> Void)? {
        didSet { canvas.onOpen = onOpen }
    }
    /// Hands over the pill's rect, top-left origin in the island window, for the pill menu.
    var onMenu: ((CGRect, NSWindow) -> Void)?
    var glance: IslandGlance? {
        didSet {
            guard glance != oldValue else { return }
            canvas.glance = glance.map { GlanceArt($0, notch: layout?.hasNotch == true) }
            canvas.setAccessibilityValue(glance.map { "\($0.title), \($0.countdown)" })
            frameChanged()
        }
    }

    override init() {
        super.init()
        backdrop.contentView = canvas
        canvas.wantsLayer = true
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.button)
        canvas.setAccessibilityLabel(NSRunningApplication.current.localizedName)
        canvas.onMenu = { [weak self] in
            guard let self, let rect = self.pillRect else { return }
            self.onMenu?(rect, self.backdrop)
        }
        canvas.canOpen = { [weak self] in
            guard let self else { return false }
            return self.canOpen?() == true && self.overlays.isEmpty && NSApp.modalWindow == nil && self.isResting
        }
        source.didFrame = { [weak self] in self?.paintFrame() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frameChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func attach(_ panel: PalettePanel, screen: NSScreen) {
        guard self.panel !== panel else { return }
        self.panel = panel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.mask = clip
        panel.hasShadow = false
        observer = PanelObserver(panel: panel, changed: { [weak self] in self?.frameChanged() })
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
        let requested = IslandSurfaceConfiguration(notch: next.notch, scale: screen.backingScaleFactor)
        let moved = layout?.screen != next.screen || layout?.notch != next.notch
        layout = next
        if let glance { canvas.glance = GlanceArt(glance, notch: next.hasNotch) }
        backdrop.setFrame(next.window, display: false)
        switch requested.update(from: configuration, paletteVisible: panel?.isVisible == true,
                                hasOverlays: !overlays.isEmpty) {
        case .keep: pendingScreen = nil
        case .deferred: pendingScreen = screen
        case .recreate:
            surface = nil
            configuration = requested
            pendingScreen = nil
        }
        if moved, let panel, panel.isVisible {
            let frame = next.contentFrame(panel.frame.size).offsetBy(dx: next.window.minX, dy: next.window.minY)
            panel.setFrameOrigin(frame.origin)
        }
        if surface != nil {
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
        metrics.compact.height = metrics.idle.height
        metrics.compact.sensorWidth = next.hasNotch ? next.notch.width : 0
        metrics.compact.edgePadding = Theme.Spacing.lg
        let inner = next.hasNotch ? Theme.Spacing.md : 0
        metrics.compact.innerPadding = .init(leading: inner, trailing: inner)
        metrics.compact.maxSlotWidth = Theme.Size.islandGlanceWing
        metrics.compact.maxWidth = next.canvas.width
        metrics.compact.balance = 0
        let surface = IslandSurface<CGSize>(
            presentation: .idle, clock: FrameClock(frameSource: source), metrics: metrics,
            motion: .standard, dpr: screen.backingScaleFactor, reduced: reducedMotion,
            keyline: 0, stageWidth: Theme.Size.panelWidth, measure: { presentation, _ in
                switch presentation {
                case .expanded(let content):
                    ContentMeasures(expandedHeight: Double(content.bottom?.height ?? 0))
                case .compact(let content):
                    ContentMeasures(leading: Double(content.leading?.width ?? 0),
                                    trailing: Double(content.trailing?.width ?? 0))
                default: ContentMeasures()
                }
            })
        self.surface = surface
        surfaceMetrics = metrics
        source.display.host = canvas
        frameChanged()
    }

    static func notch(on screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }

    @objc func frameChanged() {
        guard let surface, let layout else { return }
        surface.reduced = reducedMotion
        let sunk = panel.map { $0.isVisible && $0.level < Self.paletteLevel } ?? false
        let suspended = NSApp.modalWindow != nil || sunk
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
            } else if showsRest, let art = canvas.glance {
                if !suspended { backdrop.orderFrontRegardless() }
                let slots = CompactContent(leading: CGSize(width: art.layout.leading, height: 0),
                                           trailing: CGSize(width: art.layout.trailing, height: 0))
                surface.show(.compact(slots), contentKey: "glance")
            } else {
                if showsRest, !suspended { backdrop.orderFrontRegardless() }
                surface.show(.idle, contentKey: "rest")
            }
        }
        paintFrame()
    }

    func opened() {
        frameChanged()
    }

    static let paletteLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 1)
    static let reportLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 2)
    static let questionLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 3)

    private var reducedMotion: Bool { !Motion.isEnabled || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var isResting: Bool {
        guard let layout, let bounds = canvas.outline?.boundingBoxOfPath else { return false }
        let size = layout.hasNotch ? CGSize(width: layout.notch.width, height: layout.notch.height * 2) : Theme.Size.islandRest
        let width = canvas.glance.map { glanceWidth($0.layout) } ?? size.width
        return abs(bounds.width - width) < 0.01 && abs(bounds.height - size.height) < 0.01
    }

    private var surfaceMetrics: IslandMetrics?

    private func glanceWidth(_ glance: IslandGlanceLayout) -> Double {
        guard let full = surfaceMetrics else { return 0 }
        let metrics = full.compact
        let sides = compactSides(SlotPair(leading: glance.leading, trailing: glance.trailing), metrics: full)
        let half = metrics.maxWidth / 2
        return min(metrics.sensorWidth / 2 + sides.leading, half) + min(metrics.sensorWidth / 2 + sides.trailing, half)
    }

    /// The pill's visible part, measured from the island window's top-left corner.
    private var pillRect: CGRect? {
        guard let bounds = canvas.outline?.boundingBoxOfPath else { return nil }
        let height = canvas.bounds.height
        let top = max(height - bounds.maxY, 0)
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: height - bounds.minY - top)
    }

    func closed() {
        if let pendingScreen, panel?.isVisible != true, overlays.isEmpty {
            configure(pendingScreen)
            return
        }
        frameChanged()
    }

    func setOverlays(_ frames: [CGRect]) {
        overlays = frames
        closed()
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
        canvas.restWidth = layout.hasNotch ? layout.notch.width : Theme.Size.islandRest.width
        canvas.restHeight = layout.hasNotch ? layout.notch.height * 2 : Theme.Size.islandRest.height
        canvas.glanceWidth = canvas.glance.map { glanceWidth($0.layout) } ?? 0
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
        } else if IslandVerification.enabled, let captureName {
            self.captureName = nil
            IslandVerification.capture(captureName, backdrop: backdrop, panel: nil)
            captured.append(captureName)
        }
        #endif
    }

    #if DEBUG
    var frameIntervals: [Double] { source.intervals }
    var frameCPU: [Double] { source.cpuMilliseconds }

    var backdropWindow: NSWindow { backdrop }
    var outlineBounds: CGRect { canvas.outline?.boundingBoxOfPath ?? .zero }
    var surfaceIdentity: ObjectIdentifier? { surface.map(ObjectIdentifier.init) }
    var contentKey: String? { surface?.contentKey }
    var overlayCount: Int { overlays.count }
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
    #endif

    isolated deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        backdrop.orderOut(nil)
    }

    @MainActor
    private final class PanelObserver: NSObject {
        private let changed: () -> Void
        init(panel: NSWindow, changed: @escaping () -> Void) {
            self.changed = changed
            super.init()
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                         NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
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
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Self.levelValue)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
