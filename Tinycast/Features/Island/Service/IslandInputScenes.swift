#if DEBUG
import AppKit
import CoreGraphics

/// WindowServer mouse, pid-only keys; `Scripts/island-input-helper.swift` logs pass-through.
@MainActor
enum IslandInputScenes {
    static let names: Set = ["ws-pill", "ws-menu", "ws-busy", "ws-boundary", "ws-hover", "ws-glance-menu",
                             "ws-quit-key", "ws-quit-row"]

    static var received: [String] = []
    private static var lastRightDown: RightDown?
    private static var cursor: CGPoint?
    static var core: AppCore { AppCore.shared }
    private static var helperLog: String? { ProcessInfo.processInfo.environment["ISLAND_HELPER_LOG"] }

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        cursor = CGEvent(source: nil)?.location
        print("CURSOR_SAVED \(cursor.map { "\($0)" } ?? "nil")")
        _ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            received.append("\(event.type.rawValue)@\(event.window.map { String(describing: type(of: $0)) } ?? "nil")")
            if event.type == .rightMouseDown { lastRightDown = RightDown(event) }
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

    static func check(_ condition: Bool, _ message: String) {
        if !condition { restoreCursor(); print("RECEIVED \(received)") }
        IslandVerification.require(condition, message)
    }

    static func restoreCursor() {
        guard let cursor else { return }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cursor, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        self.cursor = nil
        print("CURSOR_RESTORED \(cursor)")
    }

    private static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
    }

    static func move(_ point: CGPoint) async {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz(point), mouseButton: .left)?
            .post(tap: .cghidEventTap)
        await IslandVerification.pause(0.05)
    }

    /// `point` is Cocoa global; WindowServer routes the event, no window is chosen here.
    static func click(_ point: CGPoint, right: Bool = false, flags: CGEventFlags = [],
                      settle: TimeInterval = 0.35) async {
        await move(point)
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        print("CLICK quartz=\(quartz(point)) right=\(right)")
        for type in types {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz(point),
                                mouseButton: right ? .right : .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            await IslandVerification.pause(0.03)
        }
        await IslandVerification.pause(settle)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) async {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(getpid())
        }
        await IslandVerification.pause(0.12)
    }

    static func typeText(_ text: String) async {
        let codes: [Character: CGKeyCode] = ["z": 6, "q": 12, "u": 32, "i": 34, "t": 17]
        for character in text { if let code = codes[character] { await key(code) } }
    }

    // MARK: - Geometry

    static func canvas(_ controller: IslandController) -> IslandCanvas? {
        controller.backdropWindow.contentView as? IslandCanvas
    }

    static func screenPoint(_ local: CGPoint, in controller: IslandController) -> CGPoint {
        let origin = controller.backdropWindow.frame.origin
        return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
    }

    static func centre(_ controller: IslandController) -> CGPoint {
        let bounds = controller.outlineBounds
        let height = controller.backdropWindow.frame.height
        return screenPoint(CGPoint(x: bounds.midX, y: (bounds.minY + min(bounds.maxY, height)) / 2), in: controller)
    }

    /// The points just inside and just outside the outline on a horizontal line, in canvas space.
    static func sideEdge(_ path: CGPath, y: CGFloat, from x: CGFloat, to end: CGFloat) -> (CGPoint, CGPoint)? {
        var probe = x
        while probe < end {
            if path.contains(CGPoint(x: probe, y: y)) {
                return (CGPoint(x: probe + 2, y: y), CGPoint(x: probe - 2, y: y))
            }
            probe += 0.25
        }
        return nil
    }

    /// Front-to-back windows holding `point`; owner and layer need no capture grant.
    static func windowsUnder(_ point: CGPoint) -> [String] {
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

    static func helperPoints(_ prefix: String) -> [CGPoint] {
        helperLines().filter { $0.hasPrefix(prefix) }.compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 4, let x = Double(parts[2]), let y = Double(parts[3]) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    static func helperClicks() -> Int { helperPoints("CLICK").count }

    private static func got(_ prefix: String, _ point: CGPoint, since count: Int) -> Bool {
        helperPoints(prefix).dropFirst(count).contains { abs($0.x - point.x) <= 1 && abs($0.y - point.y) <= 1 }
    }

    /// Where a click that must miss the island went: the helper, or a foreign window in front.
    static func passedThrough(_ point: CGPoint, clicks: Int, globals: Int, own: Int, front: String?) -> String? {
        if received.dropFirst(own).contains(where: { $0.hasPrefix("1@") }) { return nil }
        if got("CLICK", point, since: clicks) { return "helper window" }
        if got("GLOBAL", point, since: globals), let front, !front.hasPrefix("Notchcast"), !front.hasPrefix("helper") {
            return front
        }
        return nil
    }

    // MARK: - Menu

    static var menuPanel: MenuPanel? { IslandPillScenes.menuPanel }
    static var paletteVisible: Bool { IslandPillScenes.paletteVisible }

    static func expectMenu(_ controller: IslandController, _ label: String) {
        let menu = menuPanel
        print("MENU \(label) open=\(menu != nil) key=\(menu?.isKeyWindow == true)")
        check(menu != nil, "\(label) opens the pill menu")
        check(!paletteVisible, "\(label) leaves the launcher closed")
        check(menu?.parent === controller.backdropWindow, "\(label) hangs the menu on the island")
    }

    static func closeWithEscape(_ label: String) async {
        await key(53)
        await IslandVerification.pause(0.25)
        check(menuPanel == nil, "\(label) Escape closes the pill menu")
    }

    /// Cancels a context menu a right-click on the open launcher starts, so the scene never blocks.
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
        check(!paletteVisible, "WS rest-pill click never opens the launcher (#884)")
        check(menuPanel != nil, "WS rest-pill click opens the island's menu")
        check(helperClicks() == before, "WS rest-pill click does not pass through")
        check(received.contains { $0.hasPrefix("1@") && $0.contains("IslandBackdrop") }, "WS click lands on the island window")
        core.island.pillMenu.hide()
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
        let frame = IslandPillScenes.settingsWindow?.frame ?? .null
        print("SETTINGS \(frame) TEST \(IslandVerification.testScreen?.frame ?? .null)")
        check(IslandVerification.testScreen?.frame.contains(frame) == true, "Settings opens on the test display")
        check(IslandPillScenes.statusItemWindows == 0, "no menu bar item exists")
    }

    /// A WindowServer right-click on the pill opens no menu over the launcher, nor while it closes.
    private static func busy(controller: IslandController, at point: CGPoint) async {
        let rest = controller.outlineBounds
        let control = await rightClick(point, "rest control")
        check(control?.isPillHit == true, "the WS rest right-click hits the pill inside its outline")
        expectMenu(controller, "WS rest right-click")
        await closeWithEscape("rest control")
        let probe = ContextMenuProbe()
        NotificationCenter.default.addObserver(probe, selector: #selector(ContextMenuProbe.didBegin(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(probe) }
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.9)
        check(paletteVisible, "the launcher is open")
        if let exposed = exposedPillPoint(controller) {
            let open = await rightClick(exposed, "open exposed")
            check(open?.isPillHit == true, "the WS right-click over the open launcher hits the pill inside its outline")
        } else {
            print("BUSY open launcher intercepts: no backdrop point inside the outline is uncovered")
            let open = await rightClick(point, "open intercepted")
            check(open?.window == "PalettePanel", "the launcher intercepts a WS right-click on the pill")
        }
        check(menuPanel == nil && probe.began == 0, "WS right-click over the open launcher opens no menu")
        check(paletteVisible, "the launcher stays open")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        let closing = await rightClick(point, "closing")
        check(closing?.isPillHit == true, "the WS mid-close right-click hits the pill inside its outline")
        check((closing?.outline.height ?? 0) > rest.height + 1, "the WS right-click lands mid-close")
        check(menuPanel == nil && probe.began == 0, "WS right-click during the closing transition opens no menu")
        await IslandVerification.pause(0.8)
        check(controller.outlineBounds == rest && !paletteVisible, "the pill settles back at rest")
    }

    private static func rightClick(_ point: CGPoint, _ label: String) async -> RightDown? {
        lastRightDown = nil
        await click(point, right: true, settle: 0.2)
        print("BUSY \(label) at=\(point) down=\(lastRightDown.map { "\($0)" } ?? "nil") menu=\(menuPanel != nil)")
        return lastRightDown
    }

    /// A point inside the pill's current outline that no window above the backdrop covers.
    private static func exposedPillPoint(_ controller: IslandController) -> CGPoint? {
        guard let path = canvas(controller)?.outline else { return nil }
        let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow],
                                               CGWindowID(controller.backdropWindow.windowNumber)) as? [[String: Any]]
        let covers = (above ?? []).compactMap { info -> CGRect? in
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        }
        let box = path.boundingBoxOfPath.intersection(controller.backdropWindow.contentView?.bounds ?? .null)
        for y in stride(from: box.minY + 2, to: box.maxY - 2, by: 4) {
            for x in stride(from: box.minX + 2, to: box.maxX - 2, by: 4) where path.contains(CGPoint(x: x, y: y)) {
                let screen = screenPoint(CGPoint(x: x, y: y), in: controller)
                if !covers.contains(where: { $0.contains(quartz(screen)) }) { return screen }
            }
        }
        return nil
    }

    /// The window a right-down reached, and the pill outline and hit as they stood at that event.
    private struct RightDown: CustomStringConvertible {
        let window: String
        let outline: CGRect
        let inOutline: Bool

        @MainActor init(_ event: NSEvent) {
            window = event.window.map { String(describing: type(of: $0)) } ?? "nil"
            let pill = AppCore.shared.island.resting
            outline = pill?.outlineBounds ?? .null
            let canvas = pill?.backdropWindow.contentView as? IslandCanvas
            if let canvas, event.window === canvas.window {
                inOutline = canvas.outline?.contains(canvas.convert(event.locationInWindow, from: nil)) == true
            } else {
                inOutline = false
            }
        }

        var isPillHit: Bool { window == "IslandBackdrop" && inOutline }
        var description: String { "\(window) outline=\(outline) inOutline=\(inOutline)" }
    }
}
#endif
