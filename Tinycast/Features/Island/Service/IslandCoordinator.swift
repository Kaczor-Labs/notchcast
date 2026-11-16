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
    private var spaceCheck: Task<Void, Never>?
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
        presenter?.restingChanged()
        if restingGlance != nil { syncExpansion() }
        spaceChanged()
    }

    @objc func spaceChanged() {
        spaceCheck?.cancel()
        let candidates = AXIsProcessTrusted() ? Self.fullScreenCandidates(on: screens) : []
        spaceCheck = Task { [weak self] in
            let full = await Self.confirmFullScreen(candidates)
            guard !Task.isCancelled, let self else { return }
            for (id, backdrop) in backdrops { backdrop.onFullScreenSpace = full.contains(id) }
        }
    }

    /// Bounds alone match a zoomed window too, so display-wide windows are only leads.
    private static func fullScreenCandidates(on screens: [NSScreen])
        -> [(display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return screens.flatMap { screen in
            let display = CGDisplayBounds(screen.islandDisplayID)
            return windows.compactMap { info -> (display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)? in
                guard info[kCGWindowLayer as String] as? Int == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      let rect = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: rect),
                      abs(bounds.minX - display.minX) < 1, abs(bounds.width - display.width) < 1,
                      abs(bounds.maxY - display.maxY) < 1 else { return nil }
                return (screen.islandDisplayID, pid, bounds)
            }
        }
    }

    /// Off the main actor: a hung app would otherwise freeze the island for each timed-out read.
    @concurrent
    nonisolated private static func confirmFullScreen(
        _ candidates: [(display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)]) async -> Set<CGDirectDisplayID> {
        let timeout: Float = 0.25
        var fullFrames: [pid_t: [CGRect]] = [:]
        for pid in Set(candidates.map(\.pid)) {
            guard !Task.isCancelled else { return [] }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, timeout)
            var list: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success,
                  let windows = list as? [AXUIElement] else { continue }
            fullFrames[pid] = windows.compactMap { window in
                guard !Task.isCancelled else { return nil }
                AXUIElementSetMessagingTimeout(window, timeout)
                var full: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success,
                      full as? Bool == true else { return nil }
                return frame(of: window)
            }
        }
        return Set(candidates.filter { candidate in
            fullFrames[candidate.pid, default: []].contains { matches($0, candidate.bounds) }
        }.map(\.display))
    }

    nonisolated private static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var value: CFTypeRef?
        guard !Task.isCancelled,
              AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let position = value, CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin), !Task.isCancelled,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let extent = value, CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(extent, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The top edge moves with the menu bar's reveal strip, so only the other three edges must agree.
    nonisolated private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.width - b.width) < 1 && abs(a.maxY - b.maxY) < 1
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
        spaceCheck?.cancel()
    }
}

extension NSScreen {
    var islandDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
