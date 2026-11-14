#if DEBUG
import AppKit

@MainActor
enum IslandMenuScenes {
    static func run(_ scene: String, core: AppCore, panel: PalettePanel) async {
        let filter = scene == "filter-menu"
        if filter {
            core.paletteCoordinator.showPalette(mode: .clipboard)
            await IslandVerification.pause(0.3)
        }
        IslandLatency.focus(panel)
        IslandLatency.key(panel, code: filter ? 35 : 40, characters: filter ? "p" : "k", modifiers: .command)
        await IslandVerification.pause(0.3)
        guard let menu = NSApp.windows.first(where: { $0 is MenuPanel && $0.isVisible }) as? MenuPanel else {
            IslandVerification.require(false, "native menu visible after command shortcut"); return
        }
        IslandVerification.require(core.palette.menuOpen && menu.isKeyWindow && menu.parent === panel,
                                   "stock menu key window and native parent")
        IslandVerification.require(panel.frame.contains(menu.frame), "stock menu anchored inside native palette")
        core.island.active?.capture(scene)
        await IslandVerification.pause(0.3)
        if filter {
            IslandLatency.key(menu, code: 125, characters: "\u{f701}")
            IslandLatency.key(menu, code: 36, characters: "\r")
            await IslandVerification.pause(0.2)
            IslandVerification.require(core.palette.clipboardFilter == .text && !core.palette.menuOpen,
                                       "Down and Enter select native filter")
        } else {
            IslandLatency.key(menu, code: 0, characters: "z")
            await IslandVerification.pause(0.1)
            IslandVerification.require(core.palette.menuQuery == "z", "menu typing filters native rows")
            IslandLatency.key(menu, code: 53, characters: "\u{1b}")
            await IslandVerification.pause(0.1)
            IslandVerification.require(core.palette.menuQuery.isEmpty && core.palette.menuOpen,
                                       "first Escape clears menu query")
            IslandLatency.key(menu, code: 53, characters: "\u{1b}")
            await IslandVerification.pause(0.2)
            IslandVerification.require(!core.palette.menuOpen && panel.isVisible && panel.isKeyWindow,
                                       "second Escape closes menu and restores palette key")
            IslandLatency.key(panel, code: 53, characters: "\u{1b}")
            await IslandVerification.pause(0.2)
            IslandVerification.require(!panel.isVisible, "third Escape closes root palette")
        }
        print("PASS island native \(scene) shortcut, placement and keyboard")
        _exit(0)
    }
}
#endif
