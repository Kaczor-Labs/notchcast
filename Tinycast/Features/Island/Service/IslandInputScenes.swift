#if DEBUG
import AppKit
import CoreGraphics

/// WindowServer mouse and pid-only keys; `Scripts/island-input-helper.swift` logs what passes through.
@MainActor
enum IslandInputScenes {
    static let names: Set = ["ws-pill", "ws-menu", "ws-busy", "ws-boundary", "ws-hover", "ws-glance-menu",
                             "ws-quit-key", "ws-quit-row"]

    private static var received: [String] = []
    private static var lastRightDownOutline: CGRect?
    private static var cursor: CGPoint?
    private static var core: AppCore { AppCore.shared }
    private static var helperLog: String? { ProcessInfo.processInfo.environment["ISLAND_HELPER_LOG"] }

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        cursor = CGEvent(source: nil)?.location
        print("CURSOR_SAVED \(cursor.map { "\($0)" } ?? "nil")")
        _ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            received.append("\(event.type.rawValue)@\(event.window.map { String(describing: type(of: $0)) } ?? "nil")")
            if event.type == .rightMouseDown { lastRightDownOutline = AppCore.shared.island.resting?.outlineBounds }
            return event
        }
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else { check(false, "resting pill"); return }
        check(screen.frame.contains(controller.backdropWindow.frame), "pill on test display")
        print("BACKDROP \(controller.backdropWindow.frame) OUTLINE \(controller.outlineBounds)")
        check(helperLines().contains { $0.hasPrefix("READY") }, "pass-through helper is up")
        switch scene {
        case "ws-pill": await pill(controller: controller)
        case "ws-menu": await menu(controller: controller)
        case "ws-busy": await busy(controller: controller, at: centre(controller))
        case "ws-boundary": await boundary(controller: controller)
        case "ws-hover": await hover(controller: controller)
        case "ws-glance-menu": await glanceMenu(controller: controller)
        default: await quit(scene, controller: controller)
        }
        print("RECEIVED \(received)")
        restoreCursor()
        print("PASS scene \(scene) active=\(NSApp.isActive)")
        _exit(0)
    }

    // MARK: - Input

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { restoreCursor(); print("RECEIVED \(received)") }
        IslandVerification.require(condition, message)
    }

    private static func restoreCursor() {
        guard let cursor else { return }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cursor, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        self.cursor = nil
        print("CURSOR_RESTORED \(cursor)")
    }

    private static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
    }

    private static func move(_ point: CGPoint) async {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz(point), mouseButton: .left)?
            .post(tap: .cghidEventTap)
        await IslandVerification.pause(0.05)
    }

    /// `point` is in Cocoa global coordinates; WindowServer routes the event, no window is chosen here.
    private static func click(_ point: CGPoint, right: Bool = false, flags: CGEventFlags = [],
                              settle: TimeInterval = 0.35) async {
        await move(point)
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz(point),
                                mouseButton: right ? .right : .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            await IslandVerification.pause(0.03)
        }
        await IslandVerification.pause(settle)
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags = []) async {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(getpid())
        }
        await IslandVerification.pause(0.12)
    }

    private static func typeText(_ text: String) async {
        let codes: [Character: CGKeyCode] = ["z": 6, "q": 12, "u": 32, "i": 34, "t": 17]
        for character in text { if let code = codes[character] { await key(code) } }
    }

    // MARK: - Geometry

    private static func canvas(_ controller: IslandController) -> IslandCanvas? {
        controller.backdropWindow.contentView as? IslandCanvas
    }

    private static func screenPoint(_ local: CGPoint, in controller: IslandController) -> CGPoint {
        let origin = controller.backdropWindow.frame.origin
        return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
    }

    private static func centre(_ controller: IslandController) -> CGPoint {
        let bounds = controller.outlineBounds
        let height = controller.backdropWindow.frame.height
        return screenPoint(CGPoint(x: bounds.midX, y: (bounds.minY + min(bounds.maxY, height)) / 2), in: controller)
    }

    /// The points just inside and just outside the outline on a horizontal line, in canvas space.
    private static func sideEdge(_ path: CGPath, y: CGFloat, from x: CGFloat, to end: CGFloat) -> (CGPoint, CGPoint)? {
        var probe = x
        while probe < end {
            if path.contains(CGPoint(x: probe, y: y)) {
                return (CGPoint(x: probe + 2, y: y), CGPoint(x: probe - 2, y: y))
            }
            probe += 0.25
        }
        return nil
    }

    /// Front-to-back on-screen windows whose bounds hold `point`; owner and layer need no capture grant.
    private static func windowsUnder(_ point: CGPoint) -> [String] {
        let quartzPoint = quartz(point)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0,
                         height: bounds["Height"] ?? 0).contains(quartzPoint) else { return nil }
            return "\(info[kCGWindowOwnerName as String] ?? "?")#\(info[kCGWindowNumber as String] ?? 0)"
                + " layer=\(info[kCGWindowLayer as String] ?? 0) alpha=\(info[kCGWindowAlpha as String] ?? 0)"
                + " bounds=\(bounds)"
        }
    }

    // MARK: - Helper log

    private static func helperLines() -> [String] {
        guard let helperLog, let text = try? String(contentsOfFile: helperLog, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private static func helperPoints(_ prefix: String) -> [CGPoint] {
        helperLines().filter { $0.hasPrefix(prefix) }.compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 4, let x = Double(parts[2]), let y = Double(parts[3]) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private static func helperClicks() -> Int { helperPoints("CLICK").count }

    private static func got(_ prefix: String, _ point: CGPoint, since count: Int) -> Bool {
        helperPoints(prefix).dropFirst(count).contains { abs($0.x - point.x) <= 1 && abs($0.y - point.y) <= 1 }
    }

    /// Where a click that must miss the island went: the helper below, or the foreign window in front.
    private static func passedThrough(_ point: CGPoint, clicks: Int, globals: Int, own: Int, front: String?) -> String? {
        if received.dropFirst(own).contains(where: { $0.hasPrefix("1@") }) { return nil }
        if got("CLICK", point, since: clicks) { return "helper window" }
        if got("GLOBAL", point, since: globals), let front, !front.hasPrefix("Notchcast"), !front.hasPrefix("helper") {
            return front
        }
        return nil
    }

    // MARK: - Menu

    private static var menuPanel: MenuPanel? { IslandPillScenes.menuPanel }
    private static var paletteVisible: Bool { IslandPillScenes.paletteVisible }

    private static func expectMenu(_ controller: IslandController, _ label: String) {
        let menu = menuPanel
        print("MENU \(label) open=\(menu != nil) key=\(menu?.isKeyWindow == true)")
        check(menu != nil, "\(label) opens the pill menu")
        check(!paletteVisible, "\(label) leaves the launcher closed")
        check(menu?.parent === controller.backdropWindow, "\(label) hangs the menu on the island")
    }

    private static func closeWithEscape(_ label: String) async {
        await key(53)
        await IslandVerification.pause(0.25)
        check(menuPanel == nil, "\(label) Escape closes the pill menu")
    }

    /// Cancels any context menu a right-click on the open launcher starts, so the scene never blocks.
    private final class ContextMenuProbe: NSObject {
        var began = 0
        @objc func didBegin(_ note: Notification) {
            began += 1
            (note.object as? NSMenu)?.cancelTracking()
        }
    }

    // MARK: - Scenes

    private static func pill(controller: IslandController) async {
        let before = helperClicks()
        await click(centre(controller))
        await IslandVerification.pause(0.3)
        check(paletteVisible && core.palette.mode == .launcher, "WS rest-pill click opens the launcher")
        check(menuPanel == nil, "WS rest-pill click opens no menu")
        check(helperClicks() == before, "WS rest-pill click does not pass through")
        check(received.contains { $0.hasPrefix("1@") && $0.contains("IslandBackdrop") }, "WS click lands on the island window")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    private static func menu(controller: IslandController) async {
        let point = centre(controller)
        let before = helperClicks()
        await click(point, right: true)
        expectMenu(controller, "WS right-click (secondary click)")
        await typeText("zzzz")
        await IslandVerification.pause(0.2)
        print("QUERY '\(core.palette.menuQuery)' ROWS \(core.island.pillMenu.itemTitles)")
        check(core.island.pillMenu.itemTitles.isEmpty, "pid keys zzzz filter the pill menu")
        await key(53)
        await IslandVerification.pause(0.2)
        check(menuPanel != nil && core.palette.menuQuery.isEmpty, "first Escape clears the query, menu stays")
        await closeWithEscape("second")
        for (flags, label) in [(CGEventFlags.maskControl, "WS control-click"), (.maskAlternate, "WS option-click")] {
            await click(point, flags: flags)
            expectMenu(controller, label)
            await closeWithEscape(label)
        }
        check(helperClicks() == before, "no pill click passes through")
        await click(point, right: true)
        expectMenu(controller, "WS right-click before outside click")
        let outside = CGPoint(x: point.x - 300, y: point.y - 150)
        await click(outside)
        await IslandVerification.pause(0.3)
        print("OUTSIDE \(outside) menu=\(menuPanel != nil) active=\(NSApp.isActive)")
        check(got("CLICK", outside, since: before), "WS outside click reaches the window below")
        check(menuPanel == nil && core.palette.menuQuery.isEmpty, "WS outside click dismisses the pill menu")
        await click(point, right: true)
        expectMenu(controller, "WS right-click before Command-comma")
        await key(43, flags: .maskCommand)
        await IslandVerification.pause(0.6)
        check(menuPanel == nil, "Command-comma closes the pill menu")
        check(IslandPillScenes.settingsWindow?.isVisible == true, "Command-comma opens Settings")
        check(IslandPillScenes.statusItemWindows == 0, "no menu bar item exists")
    }

    /// A WindowServer right-click on the pill opens no menu over the launcher, nor while it closes.
    private static func busy(controller: IslandController, at point: CGPoint) async {
        let rest = controller.outlineBounds
        let probe = ContextMenuProbe()
        NotificationCenter.default.addObserver(probe, selector: #selector(ContextMenuProbe.didBegin(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(probe) }
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.9)
        check(paletteVisible, "the launcher is open")
        let own = received.count
        await click(point, right: true, settle: 0.2)
        print("BUSY open received=\(received.dropFirst(own)) contextMenus=\(probe.began)")
        check(received.dropFirst(own).contains { $0.hasPrefix("3@") }, "WS right-click over the open launcher hits an own window")
        check(menuPanel == nil, "WS right-click over the open launcher opens no menu")
        check(paletteVisible, "the launcher stays open")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        let closing = received.count
        lastRightDownOutline = nil
        await click(point, right: true, settle: 0.2)
        let atClick = lastRightDownOutline ?? .null
        print("BUSY closing rest=\(rest) atClick=\(atClick) received=\(received.dropFirst(closing)) contextMenus=\(probe.began)")
        check(atClick.height > rest.height + 1, "the WS right-click lands mid-close")
        check(menuPanel == nil, "WS right-click during the closing transition opens no menu")
        await IslandVerification.pause(0.8)
        check(controller.outlineBounds == rest && !paletteVisible, "the pill settles back at rest")
    }

    private static func boundary(controller: IslandController) async {
        guard let path = canvas(controller)?.outline else { check(false, "rest outline"); return }
        let bounds = path.boundingBoxOfPath
        let height = controller.backdropWindow.frame.height
        let midY = (bounds.minY + min(bounds.maxY, height)) / 2
        guard let side = sideEdge(path, y: midY, from: bounds.minX - 10, to: bounds.midX) else {
            check(false, "rest side edge"); return
        }
        let bottom = (CGPoint(x: bounds.midX, y: bounds.minY + 2), CGPoint(x: bounds.midX, y: bounds.minY - 2))
        for (name, inside, outside) in [("bottom", bottom.0, bottom.1), ("side", side.0, side.1)] {
            check(path.contains(inside) && !path.contains(outside), "\(name) probes straddle the outline")
            let insideScreen = screenPoint(inside, in: controller)
            let outsideScreen = screenPoint(outside, in: controller)
            print("PROBE rest-\(name) inside=\(insideScreen) outside=\(outsideScreen)")
            let before = helperClicks()
            await click(insideScreen, right: true)
            expectMenu(controller, "WS just inside rest-\(name)")
            check(helperClicks() == before, "WS just inside rest-\(name) does not pass through")
            await closeWithEscape("rest-\(name)")
            let clicks = helperClicks()
            let globals = helperPoints("GLOBAL").count
            let own = received.count
            let under = windowsUnder(outsideScreen)
            print("UNDER rest-\(name) \(under)")
            await click(outsideScreen)
            await IslandVerification.pause(0.2)
            let target = passedThrough(outsideScreen, clicks: clicks, globals: globals, own: own,
                                       front: under.first { !$0.hasPrefix("Notchcast") })
            print("THROUGH rest-\(name) to=\(target ?? "nil") received=\(received.dropFirst(own))")
            check(target != nil, "WS just outside rest-\(name) passes through")
            check(menuPanel == nil && !paletteVisible, "WS just outside rest-\(name) opens nothing")
        }
        await paletteEdge()
    }

    private static func paletteEdge() async {
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.9)
        guard let active = core.island.active, let path = canvas(active)?.outline,
              let palette = NSApp.windows.first(where: { $0 is PalettePanel && $0.isVisible }) else {
            check(false, "open palette island"); return
        }
        let bounds = path.boundingBoxOfPath
        let height = active.backdropWindow.frame.height
        for (name, y) in [("top", min(bounds.maxY, height) - 24), ("middle", bounds.midY)] {
            await paletteProbe(name, y: y, path: path, active: active, palette: palette)
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    private static func paletteProbe(_ name: String, y: CGFloat, path: CGPath, active: IslandController,
                                     palette: NSWindow) async {
        let bounds = path.boundingBoxOfPath
        guard let side = sideEdge(path, y: y, from: bounds.minX - 10, to: bounds.midX) else {
            check(false, "palette island side edge \(name)"); return
        }
        check(path.contains(side.0) && !path.contains(side.1), "palette probes straddle the island outline")
        let inside = screenPoint(side.0, in: active)
        let outside = screenPoint(side.1, in: active)
        print("PROBE palette-\(name) inside=\(inside) outside=\(outside) outsideInPalette=\(palette.frame.contains(outside))")
        let before = helperClicks()
        let ownBefore = received.count
        // A left click inside the result rows would launch an app, so only the search band is clicked.
        if name == "top" {
            await click(inside)
            check(helperClicks() == before, "WS just inside the palette island edge (\(name)) does not pass through")
            check(received.dropFirst(ownBefore).contains { $0.hasPrefix("1@") },
                  "WS just inside the palette island edge (\(name)) hits an own window")
        }
        let own = received.count
        let globals = helperPoints("GLOBAL").count
        let under = windowsUnder(outside)
        print("UNDER palette-\(name) \(under)")
        await click(outside)
        await IslandVerification.pause(0.2)
        let target = passedThrough(outside, clicks: before, globals: globals, own: own,
                                   front: under.first { !$0.hasPrefix("Notchcast") })
        print("PALETTE_OUTSIDE \(name) to=\(target ?? "nil") received=\(received.dropFirst(own)) visible=\(paletteVisible)")
        check(target != nil, "WS just outside the palette island edge (\(name)) passes through")
        check(!received.dropFirst(own).contains { $0.hasPrefix("1@") },
              "WS just outside the palette island edge (\(name)) reaches no own window")
    }

    private static func visibleWindows() -> Set<ObjectIdentifier> {
        Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
    }

    private static func hover(controller: IslandController) async {
        let point = centre(controller)
        let start = CGPoint(x: point.x - 300, y: point.y - 150)
        let outline = controller.outlineBounds
        let frame = controller.backdropWindow.frame
        let windows = visibleWindows()
        let before = helperClicks()
        await move(start)
        await IslandVerification.pause(0.3)
        for step in 1...10 {
            let t = CGFloat(step) / 10
            await move(CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t))
        }
        let cursor = NSEvent.mouseLocation
        print("HOVER cursor=\(cursor) pill=\(point) under=\(windowsUnder(cursor).first ?? "nil")")
        var changed = false
        for _ in 0..<30 {
            await IslandVerification.pause(0.05)
            changed = changed || controller.outlineBounds != outline || controller.backdropWindow.frame != frame
                || visibleWindows() != windows
        }
        check(abs(cursor.x - point.x) < 1 && abs(cursor.y - point.y) < 1, "WS hover: cursor rests on the pill")
        check(!changed, "WS hover leaves the rest pill, its window and the window list unchanged")
        check(!paletteVisible && menuPanel == nil, "WS hover opens nothing")
        check(helperClicks() == before, "WS hover sends no click")
        await move(start)
    }

    private static func glanceMenu(controller: IslandController) async {
        let meeting = await IslandPillScenes.previewMeeting(core: core)
        let point = centre(controller)
        await click(point, right: true)
        expectMenu(controller, "WS glance right-click")
        let titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        check(titles.first == String(localized: "Join \(MenuBarSummary.title(meeting.title))"),
              "a carded meeting leads with Join")
        await closeWithEscape("glance")
        await click(point)
        await IslandVerification.pause(0.3)
        check(paletteVisible && core.palette.mode == .launcher, "WS glance click opens the launcher")
        check(menuPanel == nil, "WS glance click opens no menu")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    private static func quit(_ scene: String, controller: IslandController) async {
        check(Bundle.main.bundleIdentifier?.hasPrefix("com.tinycast.app.v2") == true, "quit runs only in an isolated bundle")
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { _ in print("PASS \(scene) terminates the app") }
        await click(centre(controller), right: true)
        expectMenu(controller, "WS right-click")
        restoreCursor()
        if scene == "ws-quit-key" {
            await key(12, flags: .maskCommand)
        } else {
            await typeText("quit")
            await IslandVerification.pause(0.2)
            print("ROWS \(core.island.pillMenu.itemTitles)")
            check(core.island.pillMenu.itemTitles.first == CommandID.quit.name, "typing quit finds the Quit row")
            await key(36)
        }
        await IslandVerification.pause(1.5)
        check(false, "\(scene) did not terminate")
    }
}
#endif
