import AppKit
import Observation

@MainActor
final class IslandCoordinator: NSObject {
    private unowned let core: AppCore
    private var backdrops: [ObjectIdentifier: IslandController] = [:]
    private(set) var active: IslandController?
    private weak var panel: PalettePanel?
    private var started = false
    private(set) lazy var overlays = IslandOverlayController(island: self)

    init(core: AppCore) { self.core = core }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuild()
        observeVisibility()
    }

    private var screens: [NSScreen] {
        if IslandVerification.enabled {
            return NSScreen.screens.filter { $0.localizedName.contains("Agent Test") }
        }
        return NSScreen.screens
    }

    @objc private func rebuild() {
        active?.detach()
        active = nil
        backdrops = [:]
        let available = screens
        let main = available.first(where: { $0 === NSScreen.primary }) ?? available.first
        for screen in available {
            let backdrop = IslandController()
            backdrop.showsRest = screen === main
            backdrop.onOpen = { [weak self] in self?.core.paletteCoordinator.showPalette(mode: .launcher) }
            backdrop.configure(screen)
            backdrops[ObjectIdentifier(screen)] = backdrop
        }
        if let panel, panel.isVisible {
            let collapsed = core.paletteCoordinator.paletteIsCollapsed
            let outset = collapsed ? Theme.Size.paletteGlassOutset : 0
            let size = panel.frame.insetBy(dx: outset, dy: outset).size
            if let anchor = anchor(panel, width: size.width, collapsed: collapsed) {
                panel.setFrame(PalettePlacement.frame(at: anchor, size: size, outset: outset), display: true)
            }
        }
        overlays.reposition()
    }

    func overlayContext(screen preferred: NSScreen?) -> (NSScreen, IslandController, CGRect?)? {
        if !started { start() }
        let available = screens
        let current = available.first { backdrops[ObjectIdentifier($0)] === active }
        let screen = current ?? available.first(where: { $0 === preferred }) ?? available.first
        guard let screen, let controller = backdrops[ObjectIdentifier(screen)] else { return nil }
        active = controller
        return (screen, controller, panel?.isVisible == true ? panel?.frame : nil)
    }

    func anchor(_ window: NSPanel, width: CGFloat, collapsed: Bool) -> CGPoint? {
        guard let panel = window as? PalettePanel else { return nil }
        let outset = collapsed ? Theme.Size.paletteGlassOutset : 0
        if IslandVerification.stock, let screen = screens.first {
            return CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - outset)
        }
        if !started { start() }
        let available = screens
        let pointer = NSEvent.mouseLocation
        let retained = panel.isVisible ? available.first { backdrops[ObjectIdentifier($0)] === active } : nil
        let screen = retained ?? available.first(where: { $0.frame.contains(pointer) }) ?? available.first
        guard let screen, let backdrop = backdrops[ObjectIdentifier(screen)] else { return nil }
        if active !== backdrop {
            active?.detach()
            active = backdrop
        }
        self.panel = panel
        backdrop.attach(panel, screen: screen)
        let notch = IslandController.notch(on: screen)
        return CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - notch.height - outset)
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = core.palette.isVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeVisibility()
                if self.core.palette.isVisible { self.active?.opened() } else { self.active?.closed() }
            }
        }
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }
}
