#if DEBUG
import AppKit

/// `notice-queue`: a newer notice covers an older one, which returns, then waits out a level.
@MainActor
enum IslandNoticeScenes {
    static func run(core: AppCore, controller: IslandController) async {
        let presenter = core.islandPresenter
        let heard = IslandVerification.announcements.count
        func expect(_ text: String?, _ state: String) {
            print("NOTICE \(state) notice=\(controller.notice?.text ?? "nil") value=\(controller.accessibilityValue)")
            IslandVerification.require(controller.notice?.text == text, "\(state): the pill shows \(text ?? "no notice")")
        }
        presenter.post(IslandNotice(id: "older", text: "Older", seconds: 1.6), onTap: nil)
        await IslandVerification.pause(0.3)
        presenter.post(IslandNotice(id: "newer", text: "Newer", seconds: 0.6), onTap: nil)
        expect("Newer", "covered")
        IslandVerification.require(controller.accessibilityValue == "Newer", "the island says the newer notice")
        await IslandVerification.pause(0.9)
        expect("Older", "returned")
        IslandVerification.require(controller.accessibilityValue == "Older", "the island says the returning notice")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2,
                                   "each notice is announced once, the returning one not again")

        let level = IslandLevel(source: "scene", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.4)
        presenter.showLevel(level)
        IslandVerification.require(controller.accessibilityValue == "Volume, \(level.value.formatted(.percent))",
                                   "a level outranks the notice")
        await IslandVerification.pause(2.0)
        expect("Older", "after-level")
        IslandVerification.require(controller.accessibilityValue == "Older", "the notice outlives the level it waited under")
        await IslandVerification.pause(0.8)
        expect(nil, "expired")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2, "the level adds no announcement")
    }

    /// `notice-unseen`: a notice posted under the launcher, or with no resting pill, outlives its dwell.
    static func unseen(core: AppCore, controller: IslandController) async {
        let presenter = core.islandPresenter
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.5)
        IslandVerification.panel = NSApp.windows.first { $0 is PalettePanel } as? PalettePanel
        IslandVerification.require(core.palette.isVisible, "the launcher covers the pill")
        presenter.post(IslandNotice(id: "covered", text: "Covered", seconds: 0.6), onTap: nil)
        await IslandVerification.pause(1.0)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.3)
        print("UNSEEN launcher notice=\(controller.notice?.text ?? "nil")")
        IslandVerification.require(controller.notice?.text == "Covered", "a notice posted under the launcher waits for it")
        await IslandVerification.pause(0.6)
        IslandVerification.require(controller.notice == nil, "the uncovered notice then runs out its dwell")

        func screensChanged(_ screens: [NSScreen]?) async {
            IslandVerification.screens = screens
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await IslandVerification.pause(0.2)
        }
        await screensChanged([])
        IslandVerification.require(core.island.resting == nil, "no display leaves no resting pill")
        presenter.post(IslandNotice(id: "unplugged", text: "Unplugged", seconds: 0.6), onTap: nil)
        await IslandVerification.pause(1.0)
        await screensChanged(nil)
        let next = core.island.resting
        print("UNSEEN unplugged notice=\(next?.notice?.text ?? "nil")")
        IslandVerification.require(next?.notice?.text == "Unplugged", "a notice posted with no pill waits for one")
        await IslandVerification.pause(0.7)
        IslandVerification.require(next != nil && next?.notice == nil, "the replugged notice then runs out its dwell")
    }
}
#endif
