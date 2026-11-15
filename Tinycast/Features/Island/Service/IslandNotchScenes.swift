#if DEBUG
import AppKit

/// The compact launcher on a display with a notch, faked on the notchless test display.
@MainActor
enum IslandNotchScenes {
    static let names: Set = ["compact-notch", "compact-notch-change", "compact-notch-change-open", "compact-notch-late"]
    static let notch = CGSize(width: 200, height: 32)

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        IslandVerification.fakeNotch = scene == "compact-notch" ? notch : nil
        if scene == "compact-notch-late" {
            core.island.start()
            await IslandVerification.pause(0.3)
            IslandVerification.fakeNotch = notch
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await IslandVerification.pause(0.3)
        } else if scene != "compact-notch" {
            core.paletteCoordinator.showPalette(mode: .launcher)
            await IslandVerification.pause(0.6)
            if scene == "compact-notch-change" { core.paletteCoordinator.hidePalette(restoreFocus: false) }
            await IslandVerification.pause(0.4)
            IslandVerification.fakeNotch = notch
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await IslandVerification.pause(0.3)
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await IslandVerification.pause(0.4)
        }
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.8)
        guard let panel = NSApp.windows.first(where: { $0 is PalettePanel }) as? PalettePanel,
              let controller = core.island.active else {
            IslandVerification.require(false, "compact palette and active island"); return
        }
        let backdrop = controller.backdropWindow
        let outline = controller.outlineBounds
        print("NOTCH panel=\(panel.frame) level=\(panel.level.rawValue) backdrop=\(backdrop.frame)"
            + " visible=\(backdrop.isVisible) key=\(controller.contentKey ?? "nil") outline=\(outline)")
        IslandVerification.require(core.paletteCoordinator.paletteIsCollapsed, "launcher opens compact")
        IslandVerification.require(abs(panel.frame.maxY - (screen.frame.maxY - notch.height)) < 0.01,
                                   "compact panel meets notch bottom")
        IslandVerification.require(backdrop.isVisible && controller.contentKey == "palette",
                                   "island black stands behind the compact panel")
        IslandVerification.require(outline.maxY >= backdrop.frame.height
            && abs(outline.minY - (panel.frame.minY - backdrop.frame.minY)) < 0.5
            && abs(outline.width - panel.frame.width) < 0.5, "island fills screen top to compact panel bottom")
        controller.capture(scene)
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains(scene), "scene layer capture \(scene)")
        IslandScenes.pass(scene, screen: screen)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        _exit(0)
    }
}
#endif
