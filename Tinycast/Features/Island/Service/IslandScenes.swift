#if DEBUG
import AppKit

@MainActor
enum IslandScenes {
    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        core.settings.compactMode = scene == "compact"
        core.settings.interfaceSize = scene == "scale-1.1" ? .large : scene == "scale-1.2" ? .larger : .standard
        core.settings.quicklinksEnabled = true
        await core.appIndex.refresh()
        core.paletteCoordinator.showPalette(mode: .launcher)
        guard let panel = NSApp.windows.first(where: { $0 is PalettePanel }) as? PalettePanel else {
            IslandVerification.require(false, "stock lifecycle created palette"); return
        }
        IslandVerification.panel = panel
        await IslandVerification.pause(0.8)
        IslandVerification.require(screen.frame.contains(panel.frame), "stock panel pinned to test display")
        if scene == "latency" { await IslandLatency.run(core: core, panel: panel); return }
        if scene == "keyboard" { await keyboard(core: core, panel: panel); return }
        if scene == "window-contract" { await IslandWindowScenes.run(core: core, panel: panel); return }
        if scene == "level-contract" { await IslandLevelScenes.run(core: core, panel: panel); return }
        if scene == "question" { await IslandOverlayScenes.question(core: core, panel: panel); return }
        if scene == "report" { await IslandOverlayScenes.report(core: core, panel: panel); return }
        if scene == "overlay-lifetime" { await IslandOverlayScenes.lifetime(core: core, panel: panel); return }
        if scene == "action-menu" || scene == "filter-menu" {
            await IslandMenuScenes.run(scene, core: core, panel: panel); return
        }
        switch scene {
        case "clipboard":
            core.clipboardStore.open()
            core.clipboardStore.load()
            core.clipboardStore.addText("Synthetic clipboard entry for island verification.",
                                        sourceBundleID: "com.tinycast.app.v2shell")
            core.paletteCoordinator.showPalette(mode: .clipboard)
        case "emoji":
            await core.emojiIndex.load(languages: ["en"])
            core.paletteCoordinator.showPalette(mode: .emoji)
        case "form":
            core.quicklinkCoordinator.createQuicklink(name: "Example search", link: "https://example.com/search?q={query}", openWithBundleID: nil)
        case "compact": break
        default:
            IslandLatency.focus(panel)
            for character in "saf" { IslandLatency.key(panel, code: 0, characters: String(character)) }
            await IslandVerification.pause(0.15)
            IslandVerification.require(core.palette.query == "saf", "typed query saf")
        }
        await IslandVerification.pause(0.8)
        let top = screen.frame.maxY - IslandController.notch(on: screen).height
        IslandVerification.require(abs(panel.frame.maxY - top) < 0.01, "native panel meets island top")
        guard let controller = core.island.active else { IslandVerification.require(false, "active island"); return }
        controller.capture(scene)
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains(scene), "scene layer capture \(scene)")
        let windows = NSApp.windows.filter(\.isVisible)
        IslandVerification.require(windows.allSatisfy { screen.frame.contains($0.frame) }, "all own windows on test display")
        for window in windows {
            print("WINDOW \(type(of: window)) frame=\(window.frame) level=\(window.level.rawValue) key=\(window.isKeyWindow)")
        }
        print("PASS scene \(scene) active=\(NSApp.isActive)")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        _exit(0)
    }
    private static func keyboard(core: AppCore, panel: PalettePanel) async {
        IslandLatency.focus(panel)
        IslandLatency.key(panel, code: 125, characters: "\u{f701}")
        await IslandVerification.pause(0.1)
        IslandVerification.require(core.palette.selection == 1, "Down selects next row")
        IslandLatency.key(panel, code: 126, characters: "\u{f700}")
        await IslandVerification.pause(0.1)
        IslandVerification.require(core.palette.selection == 0, "Up selects previous row")
        for character in "Clipboard History" { IslandLatency.key(panel, code: 0, characters: String(character)) }
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.palette.query == "Clipboard History", "native typing updates query")
        IslandLatency.key(panel, code: 36, characters: "\r")
        await IslandVerification.pause(0.3)
        IslandVerification.require(core.palette.mode == .clipboard, "Enter opens internal clipboard command")
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.palette.mode == .launcher && panel.isVisible, "Escape returns through screen stack")
        core.palette.query = ""
        IslandLatency.key(panel, code: 48, characters: "\t")
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.palette.mode != .launcher, "Tab advances screen ring")
        core.quicklinkCoordinator.createQuicklink(name: "Focus fixture", link: "https://example.com/{query}", openWithBundleID: nil)
        await IslandVerification.pause(0.3)
        let before = panel.firstResponder
        IslandLatency.key(panel, code: 48, characters: "\t")
        await IslandVerification.pause(0.2)
        IslandVerification.require(panel.firstResponder != nil && panel.firstResponder !== before, "Tab advances form focus")
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.2)
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.2)
        IslandVerification.require(!panel.isVisible && !core.palette.isVisible, "Escape closes root palette")
        print("PASS keyboard live native typing arrows Enter Escape Tab form focus")
        _exit(0)
    }
}
#endif
