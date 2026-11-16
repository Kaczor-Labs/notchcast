#if DEBUG
import AppKit

/// The volume commands' level, fed straight to the presenter so the Mac's own volume never changes.
@MainActor
enum IslandVolumeScenes {
    private static var presenter: IslandPresenter? { AppCore.shared.islandPresenter as? IslandPresenter }
    private static var band: NSWindow? { NSApp.windows.first { $0 is HUDPanel && $0.isVisible } }
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private static func until(_ time: Double) async { await IslandVerification.pause(max(0, time - now)) }

    /// Sixty calls over two seconds, as a held Volume Up key repeats them.
    private static func burst() async -> Double {
        for call in 0..<60 {
            AppCore.shared.islandPresenter.showLevel(VolumeLevel.island(Float32(call) / 59, muted: false))
            await IslandVerification.pause(2.0 / 60)
        }
        return now
    }

    static func rest(core: AppCore, screen: NSScreen) async {
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        IslandVerification.require(screen.frame.contains(controller.backdropWindow.frame), "pill on test display")
        let rest = controller.outlineBounds.width
        let before = presenter?.presentations ?? -1
        let last = await burst()
        print("LEVEL rest=\(rest) width=\(controller.outlineBounds.width) presentations=\(presenter?.presentations ?? 0)")
        IslandVerification.require(presenter?.presentations == before + 1, "60 calls in 2 s give one presentation")
        IslandVerification.require(controller.contentKey == "glance" && controller.level != nil, "the level is in the pill")
        IslandVerification.require(controller.outlineBounds.width > rest + 1, "the level widens the pill")
        IslandVerification.require(NSApp.windows.filter(\.isVisible).allSatisfy { $0 === controller.backdropWindow },
                                   "the island is the only window: no box at the bottom of the screen")
        await controller.capture("volume-level")
        await until(last + 1.2)
        IslandVerification.require(controller.level != nil, "still showing 1.2 s after the last call")
        await until(last + 1.9)
        IslandVerification.require(controller.level == nil && controller.contentKey == "rest", "back at rest after 1.5 s")
        await controller.capture("volume-rest")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["volume-level", "volume-rest"], "level and rest captured")
        IslandScenes.pass("volume", screen: screen)
        _exit(0)
    }

    static func palette(core: AppCore, panel: PalettePanel, screen: NSScreen) async {
        guard let controller = core.island.active else { IslandVerification.require(false, "active island"); return }
        core.islandPresenter.showLevel(VolumeLevel.island(0.6, muted: false))
        await IslandVerification.pause(0.4)
        guard let band else { IslandVerification.require(false, "the level shows under the palette"); return }
        print("BAND \(band.frame) PALETTE \(panel.frame)")
        IslandVerification.require(band.frame.maxY <= panel.frame.minY && abs(band.frame.midX - panel.frame.midX) < 1,
                                   "the level is stacked under the palette")
        IslandVerification.require(controller.overlayCount == 1, "the island wraps the stacked level")
        IslandVerification.require(core.island.resting?.level == nil, "the pill keeps no level under the palette")
        await controller.capture("volume-palette")
        await IslandVerification.pause(0.3)
        let before = presenter?.presentations
        core.islandPresenter.showLevel(IslandLevel(source: "scene", symbol: "sun.max.fill", label: "Scene",
                                                   value: 1.1, range: -0.25...1.25))
        let last = now
        await IslandVerification.pause(0.1)
        IslandVerification.require(presenter?.presentations == before, "a repeat replaces in place")
        await controller.capture("level-zones")
        await until(last + 1.9)
        IslandVerification.require(band.isVisible == false && controller.overlayCount == 0, "the band leaves after 1.5 s")
        IslandVerification.require(controller.captured.contains("volume-palette")
                                   && controller.captured.contains("level-zones"), "stacked levels captured")
        IslandScenes.pass("volume-palette", screen: screen)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        _exit(0)
    }

    /// The palette opens, then closes, mid-dwell with no level call after either change.
    static func paletteOpen(core: AppCore, screen: NSScreen) async {
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        let before = presenter?.presentations ?? -1
        core.islandPresenter.showLevel(VolumeLevel.island(0.6, muted: false))
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.level != nil && band == nil, "the level starts in the pill")
        await controller.capture("volume-open-pill")
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.5)
        IslandVerification.panel = NSApp.windows.first { $0 is PalettePanel } as? PalettePanel
        guard let panel = IslandVerification.panel, panel.isVisible, let band else {
            IslandVerification.require(false, "the palette opens and the band appears"); return
        }
        print("OPEN band=\(band.frame) palette=\(panel.frame) pillLevel=\(controller.level != nil)")
        IslandVerification.require(band.frame.maxY <= panel.frame.minY, "the band sits under the palette")
        IslandVerification.require(controller.level == nil, "the pill no longer draws the level")
        IslandVerification.require(presenter?.presentations == before + 1, "opening keeps the one presentation")
        await controller.capture("volume-palette-open")
        core.islandPresenter.showLevel(VolumeLevel.island(0.7, muted: false))
        let last = now
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.6)
        print("CLOSED pillLevel=\(controller.level != nil) overlays=\(controller.overlayCount) band=\(self.band != nil)")
        IslandVerification.require(controller.level != nil && controller.overlayCount == 0 && self.band == nil,
                                   "closing the palette moves the level back to the pill and frees the band's frame")
        IslandVerification.require(presenter?.presentations == before + 1, "closing keeps the one presentation")
        await controller.capture("volume-palette-closed")
        await until(last + 1.9)
        IslandVerification.require(controller.level == nil && self.band == nil && controller.overlayCount == 0,
                                   "expiry clears pill and band")
        IslandVerification.require(controller.captured == ["volume-open-pill", "volume-palette-open",
                                                           "volume-palette-closed"], "pill, band and pill captured")
        IslandScenes.pass("volume-palette-open", screen: screen)
        _exit(0)
    }
}
#endif
