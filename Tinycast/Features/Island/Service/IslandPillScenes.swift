#if DEBUG
import AppKit

/// The resting pill's scenes: they run before the launcher opens, so the pill stays at rest.
@MainActor
enum IslandPillScenes {
    static let names: Set = ["pill-menu", "pill-settings", "glance"]

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        IslandVerification.require(screen.frame.contains(controller.backdropWindow.frame), "pill on test display")
        switch scene {
        case "pill-menu": await menu(core: core, controller: controller)
        case "pill-settings": await settings(core: core, controller: controller)
        default: await glance(core: core, controller: controller)
        }
        let windows = NSApp.windows.filter(\.isVisible)
        IslandVerification.require(windows.allSatisfy { screen.frame.contains($0.frame) }, "all own windows on test display")
        for window in windows {
            print("WINDOW \(type(of: window)) frame=\(window.frame) level=\(window.level.rawValue) key=\(window.isKeyWindow)")
        }
        print("PASS scene \(scene) active=\(NSApp.isActive)")
        _exit(0)
    }

    private static var menuPanel: MenuPanel? {
        NSApp.windows.first { $0 is MenuPanel && $0.isVisible } as? MenuPanel
    }

    private static var paletteVisible: Bool {
        NSApp.windows.contains { $0 is PalettePanel && $0.isVisible }
    }

    private static var statusItemWindows: Int {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }.count
    }

    private static func openMenu(_ controller: IslandController, _ type: NSEvent.EventType,
                                 modifiers: NSEvent.ModifierFlags = [], _ label: String) async -> MenuPanel? {
        controller.clickBackdrop(type, modifiers: modifiers)
        await IslandVerification.pause(0.35)
        guard let menu = menuPanel else { IslandVerification.require(false, "\(label) opens the pill menu"); return nil }
        IslandVerification.require(!paletteVisible, "\(label) leaves the launcher closed")
        IslandVerification.require(menu.parent === controller.backdropWindow, "\(label) hangs the menu on the island")
        IslandVerification.require(menu.isKeyWindow, "\(label) menu takes key for typing")
        return menu
    }

    private static func closeMenu(_ menu: MenuPanel, _ label: String) async {
        IslandLatency.key(menu, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.35)
        IslandVerification.require(menuPanel == nil, "\(label) Escape closes the pill menu")
    }

    private static func menu(core: AppCore, controller: IslandController) async {
        guard let menu = await openMenu(controller, .rightMouseDown, "right-click"),
              let pill = controller.pillFrame else { return }
        let backdrop = controller.backdropWindow.frame
        let pillBottom = backdrop.maxY - pill.maxY
        print("PILL \(pill) BOTTOM \(pillBottom) MENU \(menu.frame)")
        IslandVerification.require(menu.frame.maxY <= pillBottom + 0.5, "menu sits below the pill")
        IslandVerification.require(pillBottom - menu.frame.maxY < 40, "menu hangs right under the pill")
        let titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        IslandVerification.require(titles.last == CommandID.quit.name, "Quit closes the pill menu")
        IslandVerification.require(titles.contains(String(localized: "Settings…")), "pill menu offers Settings")
        IslandVerification.require(!titles.contains { $0.hasPrefix(String(localized: "Join \("")")) },
                                   "no meeting, no join row")
        controller.capture("pill-menu")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("pill-menu"), "pill menu layer capture")
        for character in "zzzz" { IslandLatency.key(menu, code: 6, characters: String(character)) }
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.itemTitles.isEmpty, "typing filters the pill menu")
        IslandLatency.key(menu, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.2)
        IslandVerification.require(menuPanel != nil && core.palette.menuQuery.isEmpty, "first Escape clears the search")
        await closeMenu(menu, "right-click")
        for (modifier, label) in [(NSEvent.ModifierFlags.control, "control-click"), (.option, "option-click")] {
            guard let again = await openMenu(controller, .leftMouseDown, modifiers: modifier, label) else { return }
            await closeMenu(again, label)
        }
        controller.clickBackdrop(.rightMouseDown)
        await IslandVerification.pause(0.35)
        guard let reopened = menuPanel else { IslandVerification.require(false, "menu reopens"); return }
        IslandLatency.key(reopened, code: 43, characters: ",", modifiers: .command)
        await IslandVerification.pause(0.6)
        IslandVerification.require(menuPanel == nil, "Command-comma closes the pill menu")
        IslandVerification.require(settingsWindow?.isVisible == true, "Command-comma opens Settings")
        IslandVerification.require(statusItemWindows == 0, "no menu bar item exists")
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.frameAutosaveName == "SettingsWindow" }
    }

    private static func settings(core: AppCore, controller: IslandController) async {
        guard let menu = await openMenu(controller, .rightMouseDown, "right-click") else { return }
        let settings = String(localized: "Settings…")
        for character in settings.prefix(5) { IslandLatency.key(menu, code: 0, characters: String(character)) }
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.itemTitles.first == settings, "search finds Settings")
        IslandLatency.key(menu, code: 36, characters: "\r")
        await IslandVerification.pause(0.8)
        guard let window = settingsWindow, window.isVisible else {
            IslandVerification.require(false, "Return on Settings opens Settings"); return
        }
        IslandVerification.require(statusItemWindows == 0, "no menu bar item exists")
        for tab in [SettingsTab.general, .notes, .calendar] {
            core.settingsCoordinator.showSettings(tab: tab)
            await IslandVerification.pause(0.7)
            still(window, name: "settings-\(tab.slug)")
        }
    }

    private static func still(_ window: NSWindow, name: String) {
        guard let output = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"],
              let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            IslandVerification.require(false, "\(name) bitmap allocated"); return
        }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            IslandVerification.require(false, "\(name) PNG encoding"); return
        }
        do { try data.write(to: URL(filePath: output + "/" + name + ".png")) } catch {
            IslandVerification.require(false, "\(name) PNG write \(error)")
        }
        print("CAPTURE \(name) WINDOW \(window.frame)")
    }

    private static func glance(core: AppCore, controller: IslandController) async {
        let now = Date()
        let meeting = MeetingEvent(id: "glance", title: "Weekly product sync", start: now + 4 * 60,
            end: now + 34 * 60, isAllDay: false, isDeclined: false, calendarID: "c", calendarName: "Work",
            calendarColor: nil, calendarItemID: "i", link: MeetingLink.detect(in: "https://us02web.zoom.us/j/123456789"))
        let rest = controller.outlineBounds.width
        core.island.glance.preview(meeting, now: now)
        await IslandVerification.pause(0.9)
        let width = controller.outlineBounds.width
        print("GLANCE rest=\(rest) width=\(width) target=\(controller.glanceWidthTarget) title=\(controller.showsGlanceTitle)")
        IslandVerification.require(width > rest + 1, "the glance widens the pill")
        IslandVerification.require(abs(width - controller.glanceWidthTarget) < 0.5, "the pill settles at the glance width")
        controller.capture("glance")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("glance"), "glance layer capture")
        guard let menu = await openMenu(controller, .rightMouseDown, "glance right-click") else { return }
        let titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        IslandVerification.require(titles.first == String(localized: "Join \(MenuBarSummary.title(meeting.title))"),
                                   "a carded meeting leads the menu with Join")
        controller.capture("pill-menu-meeting")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("pill-menu-meeting"), "meeting menu layer capture")
        await closeMenu(menu, "glance")
        controller.clickBackdrop(.leftMouseDown)
        await IslandVerification.pause(0.4)
        IslandVerification.require(paletteVisible && core.palette.mode == .launcher, "a click on the glance opens the launcher")
        IslandVerification.require(menuPanel == nil, "a click on the glance opens no menu")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }
}
#endif
