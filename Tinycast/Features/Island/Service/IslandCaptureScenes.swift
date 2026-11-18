#if DEBUG
import AppKit

/// "Show in screenshots and videos" reaches every visible untitled Notchcast window live.
@MainActor
enum IslandCaptureScenes {
    static func run(core: AppCore) async {
        let key = AppSettingsKey.islandShowsInCaptures.rawValue
        if UserDefaults.standard.object(forKey: key) == nil {
            IslandVerification.require(core.settings.islandShowsInCaptures, "captures are shown by default")
        } else {
            print("STALE \(key) left by an earlier failed run; default not checked this run")
            core.settings.islandShowsInCaptures = true
            await IslandVerification.pause(0.3)
        }
        requireSharing(.readOnly, menu: nil, "default")
        if core.island.resting?.canvas.look == .frosted {
            IslandVerification.require(!liftWindows().isEmpty, "a Frosted pill's lift is checked too")
        }
        guard let menu = await openMenu(core, "default") else { return }
        requireSharing(.readOnly, menu: menu, "menu open, default")
        await turn(core, false)
        requireSharing(.none, menu: menu, "turned off with the menu open")
        print("CAPTURE_STATE off")
        await IslandVerification.pause(1.5)
        await closeMenu(menu)
        guard let hiddenMenu = await openMenu(core, "off") else { return }
        requireSharing(.none, menu: hiddenMenu, "menu reopened while off")
        await turn(core, true)
        requireSharing(.readOnly, menu: hiddenMenu, "turned back on with the menu open")
        let reshownOpen = Set(islandWindows().map(\.windowNumber))
        await turn(core, false)
        await IslandVerification.pause(0.4)
        IslandVerification.require(IslandPillScenes.menuPanel == nil, "turning off again closes the reshown open menu")
        requireReplaced(reshownOpen, "turned off again with the menu open")
        requireSharing(.none, menu: nil, "turned off again with the menu open")
        await turn(core, true)
        requireSharing(.readOnly, menu: nil, "turned on after the menu closed")
        guard let shownMenu = await openMenu(core, "on") else { return }
        requireSharing(.readOnly, menu: shownMenu, "menu reopened while on")
        print("CAPTURE_STATE on")
        await IslandVerification.pause(1.5)
        await closeMenu(shownMenu)
        let reshown = Set(islandWindows().map(\.windowNumber))
        weak let replaced = core.island.resting
        await turn(core, false)
        requireReplaced(reshown, "turned off again")
        IslandVerification.require(replaced == nil, "the replaced pill is released")
        requireSharing(.none, menu: nil, "turned off again")
        guard let again = await openMenu(core, "off again") else { return }
        requireSharing(.none, menu: again, "menu opened while off again")
        await closeMenu(again)
        core.paletteCoordinator.showPalette(mode: .launcher)
        core.showMessage("Synthetic report")
        await IslandVerification.pause(0.5)
        IslandVerification.require(NSApp.windows.contains { $0 is PalettePanel && $0.isVisible }, "launcher shown")
        requireSharing(.none, menu: nil, "launcher and a report shown while off")
        let titled = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled],
                              backing: .buffered, defer: false)
        titled.isReleasedWhenClosed = false
        titled.orderFrontRegardless()
        await IslandVerification.pause(0.3)
        await turn(core, true)
        await turn(core, false)
        IslandVerification.require(titled.isVisible, "a titled window is shown while off")
        requireSharing(.none, menu: nil, "a titled window shown while off")
        titled.close()
        await turn(core, true)
        requireSharing(.readOnly, menu: nil, "turned on at the end")
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func turn(_ core: AppCore, _ shows: Bool) async {
        core.settings.islandShowsInCaptures = shows
        await IslandVerification.pause(0.3)
    }

    private static func openMenu(_ core: AppCore, _ label: String) async -> MenuPanel? {
        guard let pill = core.island.resting else { IslandVerification.require(false, "\(label): pill"); return nil }
        var waited = 0.0
        while !pill.acceptsClicks, waited < 2.5 { await IslandVerification.pause(0.05); waited += 0.05 }
        IslandVerification.require(pill.acceptsClicks, "\(label): the pill accepts clicks")
        pill.clickBackdrop(.rightMouseDown)
        await IslandVerification.pause(0.35)
        let menu = IslandPillScenes.menuPanel
        IslandVerification.require(menu != nil, "\(label): the pill opens its menu")
        return menu
    }

    private static func closeMenu(_ menu: MenuPanel) async {
        IslandLatency.key(menu, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.5)
    }

    private static func requireReplaced(_ reshown: Set<Int>, _ label: String) {
        let renewed = Set(islandWindows().map(\.windowNumber))
        print("RENEWED \(label) reshown=\(reshown.sorted()) now=\(renewed.sorted())")
        IslandVerification.require(renewed.isDisjoint(with: reshown), "\(label): each reshown window is replaced")
    }

    private static func islandWindows() -> [NSWindow] {
        NSApp.windows.filter { $0 is IslandBackdrop && $0.isVisible }
    }

    /// Frosted's shadow windows, attached under a backdrop.
    private static func liftWindows() -> [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)) == "IslandLiftWindow" && $0.isVisible }
    }

    /// Reads WindowServer, which capture obeys: AppKit's getter keeps reporting `.none` once set.
    private static func requireSharing(_ expected: NSWindow.SharingType, menu: MenuPanel?, _ label: String) {
        let backdrops = islandWindows()
        let shown = NSApp.windows.filter { $0.isVisible || $0 === menu }
        let served = shown.map { serverSharing($0.windowNumber) }
        let wanted = shown.map { Int(($0.styleMask.contains(.titled) ? .readOnly : expected).rawValue) }
        print("SHARING \(label) lifts=\(liftWindows().count) server=\(served.map { $0.map(String.init) ?? "nil" })")
        IslandVerification.require(!backdrops.isEmpty, "\(label): island windows exist")
        IslandVerification.require(served == wanted, "\(label): every visible window, titled ones always shown")
    }

    private static func serverSharing(_ number: Int) -> Int? {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]]
        return info?.first?[kCGWindowSharingState as String] as? Int
    }
}
#endif
