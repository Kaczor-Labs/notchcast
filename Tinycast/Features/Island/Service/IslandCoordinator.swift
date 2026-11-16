import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute keys are constant C globals.
@preconcurrency import ApplicationServices
import Observation

@MainActor
final class IslandCoordinator: NSObject {
    private unowned let core: AppCore
    private var backdrops: [CGDirectDisplayID: IslandController] = [:]
    private(set) var active: IslandController?
    private weak var panel: PalettePanel?
    private var started = false
    private(set) lazy var overlays = IslandOverlayController(island: self)
    var paletteLevel: NSWindow.Level { IslandVerification.stock ? .palette : IslandController.paletteLevel }
    private(set) lazy var pillMenu = IslandPillMenu(core: core)
    private(set) lazy var glance = IslandCalendarGlance(core: core) { [weak self] in self?.showGlance($0) }
    private var restingGlance: IslandGlance?
    private(set) lazy var update = IslandUpdateActivity(core: core)

    init(core: AppCore) { self.core = core }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(modalChanged), name: name, object: nil)
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: name,
                                                              object: nil)
        }
        rebuild()
        observeVisibility()
        glance.start()
        update.start()
    }

    var resting: IslandController? { backdrops.values.first { $0.showsRest } }

    private func showGlance(_ next: IslandGlance?) {
        restingGlance = next
        syncExpansion()
        for controller in backdrops.values { controller.glance = controller.showsRest ? next : nil }
    }

    private var screens: [NSScreen] {
        #if DEBUG
        if IslandVerification.enabled {
            return IslandVerification.screens ?? IslandVerification.testScreen.map { [$0] } ?? []
        }
        #endif
        return NSScreen.screens
    }

    @objc private func rebuild() {
        let presenter = core.islandPresenter as? IslandPresenter
        let available = screens
        let connected = Set(available.map(\.islandDisplayID))
        for (id, controller) in backdrops where !connected.contains(id) {
            if active === controller { controller.detach(); active = nil }
            presenter?.restore(controller, resting: false)
            backdrops[id] = nil
        }
        let main = available.first(where: { $0.islandDisplayID == NSScreen.primary?.islandDisplayID }) ?? available.first
        for screen in available {
            let backdrop = backdrops[screen.islandDisplayID] ?? IslandController()
            backdrop.showsRest = screen.islandDisplayID == main?.islandDisplayID
            backdrop.canOpen = { [weak self] in self?.panel?.isVisible != true }
            backdrop.onOpen = { [weak self, weak backdrop] in
                if backdrop?.showsRest == true, let tap = presenter?.tap { return tap() }
                self?.core.paletteCoordinator.showPalette(mode: .launcher)
            }
            backdrop.onMenu = { [weak self] pill, window in self?.pillMenu.toggle(below: pill, in: window) }
            backdrop.glance = backdrop.showsRest ? restingGlance : nil
            presenter?.restore(backdrop, resting: backdrop.showsRest)
            backdrop.configure(screen)
            backdrops[screen.islandDisplayID] = backdrop
        }
        overlays.reposition()
        if restingGlance != nil { syncExpansion() }
        spaceChanged()
    }

    @objc func spaceChanged() {
        let trusted = AXIsProcessTrusted()
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for screen in screens {
            backdrops[screen.islandDisplayID]?.onFullScreenSpace = trusted && Self.fullScreen(screen, windows: windows)
        }
    }

    /// Short, so a hung app can't stall the main actor on a Space change.
    private static let fullScreenTimeout: Float = 0.25

    /// Bounds alone match a zoomed window too, so the topmost display-wide window's app must confirm.
    private static func fullScreen(_ screen: NSScreen, windows: [[String: Any]]) -> Bool {
        let display = CGDisplayBounds(screen.islandDisplayID)
        let owner = windows.first { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let rect = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rect) else { return false }
            return abs(bounds.minX - display.minX) < 1 && abs(bounds.width - display.width) < 1
                && abs(bounds.maxY - display.maxY) < 1
        }?[kCGWindowOwnerPID as String] as? pid_t
        guard let owner else { return false }
        let app = AXUIElementCreateApplication(owner)
        AXUIElementSetMessagingTimeout(app, fullScreenTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        return windows.contains { window in
            AXUIElementSetMessagingTimeout(window, fullScreenTimeout)
            var full: CFTypeRef?
            var origin: CFTypeRef?
            var point = CGPoint.zero
            guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success,
                  full as? Bool == true,
                  AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &origin) == .success,
                  let origin, CFGetTypeID(origin) == AXValueGetTypeID(),
                  AXValueGetValue(unsafeDowncast(origin, to: AXValue.self), .cgPoint, &point) else { return false }
            return abs(point.x - display.minX) < 1
        }
    }

    /// Also after a rebuild, so a new resting pill picks up an expansion already showing.
    private func syncExpansion() {
        (core.islandPresenter as? IslandPresenter)?.meetingChanged(glance.occurrence)
    }

    func overlayContext(screen preferred: NSScreen?) -> (NSScreen, IslandController, CGRect?)? {
        if !started { start() }
        let available = screens
        let id = IslandScreenSelection.choose(available: available.map(\.islandDisplayID),
            preferred: preferred?.islandDisplayID, retained: panel?.isVisible == true ? panel?.screen?.islandDisplayID : nil)
        guard let screen = available.first(where: { $0.islandDisplayID == id }),
              let controller = backdrops[screen.islandDisplayID] else { return nil }
        let palette = panel.flatMap { $0.isVisible && $0.screen?.islandDisplayID == id ? $0.frame : nil }
        return (screen, controller, palette)
    }

    func anchor(_ window: NSPanel, width: CGFloat, collapsed: Bool) -> CGPoint? {
        guard let panel = window as? PalettePanel else { return nil }
        let outset = collapsed ? Theme.Size.paletteGlassOutset : 0
        #if DEBUG
        if IslandVerification.stock, let screen = screens.first {
            return CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - outset)
        }
        #endif
        if !started { start() }
        let available = screens
        let pointer = NSEvent.mouseLocation
        let retained = panel.isVisible ? available.first { backdrops[$0.islandDisplayID] === active } : nil
        let id = IslandScreenSelection.choose(available: available.map(\.islandDisplayID),
            preferred: retained?.islandDisplayID,
            retained: available.first(where: { $0.frame.contains(pointer) })?.islandDisplayID)
        guard let screen = available.first(where: { $0.islandDisplayID == id }),
              let backdrop = backdrops[screen.islandDisplayID] else { return nil }
        if active !== backdrop {
            active?.detach()
            active = backdrop
        }
        self.panel = panel
        backdrop.attach(panel, screen: screen)
        let notch = IslandController.notch(on: screen)
        return CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - notch.height - outset)
    }

    var questionScreen: NSScreen? {
        #if DEBUG
        if IslandVerification.enabled { return screens.first }
        #endif
        return panel?.isVisible == true ? panel?.screen : NSScreen.underCursor
    }

    @objc private func modalChanged() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(modalEnded), object: nil)
        if NSApp.modalWindow != nil {
            // Default-mode work resumes after the nested modal loop ends.
            perform(#selector(modalEnded), with: nil, afterDelay: 0, inModes: [.default])
        } else {
            modalEnded()
        }
    }

    @objc private func modalEnded() {
        if NSApp.modalWindow == nil, let panel, panel.isVisible, panel.level < paletteLevel {
            panel.level = paletteLevel
        }
        for controller in backdrops.values { controller.frameChanged() }
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = core.palette.isVisible
            _ = core.settings.animationsEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeVisibility()
                if self.core.palette.isVisible { self.active?.opened() } else { self.active?.closed() }
            }
        }
    }

    isolated deinit {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

extension NSScreen {
    var islandDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
