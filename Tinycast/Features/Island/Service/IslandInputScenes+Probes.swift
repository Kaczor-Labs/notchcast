#if DEBUG
import AppKit
import CoreGraphics

/// The ws-* edge, hover, glance and quit scenes; the WindowServer input itself lives beside them.
@MainActor
extension IslandInputScenes {
    static func boundary(controller: IslandController) async {
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
        // A left click in the result rows would launch an app, so only the search band is clicked.
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

    static func hover(controller: IslandController) async {
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

    static func glanceMenu(controller: IslandController) async {
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

    static func quit(_ scene: String, controller: IslandController) async {
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
