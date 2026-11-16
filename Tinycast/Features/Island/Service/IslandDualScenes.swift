#if DEBUG
import AppKit

/// Two test displays held by one vdisplay wrapper: one backdrop each, the rest pill on exactly one.
@MainActor
enum IslandDualScenes {
    static let names: Set = ["dual-display"]

    static func run(core: AppCore, screen: NSScreen) async {
        let screens = IslandVerification.testScreens
        IslandVerification.require(screens.count == 2, "ISLAND_TEST_DISPLAY and ISLAND_TEST_DISPLAY_2 name two displays")
        let ids = screens.map(\.islandDisplayID)
        IslandVerification.require(Set(ids).count == 2 && !screens[0].frame.intersects(screens[1].frame),
                                   "the two test displays are distinct and do not overlap")
        core.island.start()
        await IslandVerification.pause(0.5)
        let backdrops = core.island.backdropControllers
        IslandVerification.require(Set(backdrops.keys) == Set(ids), "one backdrop per test display and no other")
        for screen in screens {
            guard let controller = backdrops[screen.islandDisplayID] else { continue }
            let frame = controller.backdropWindow.frame
            print("BACKDROP display=\(screen.islandDisplayID) frame=\(frame) screen=\(screen.frame)")
            IslandVerification.require(screen.frame.contains(frame), "backdrop \(screen.islandDisplayID) sits on its own display")
        }
        let resting = backdrops.filter { $0.value.showsRest }
        IslandVerification.require(resting.count == 1, "the rest pill is on exactly one display, got \(resting.count)")
        guard let (restID, controller) = resting.first else { return }
        IslandVerification.require(core.island.resting === controller, "the coordinator's resting pill is that one")
        for _ in 0..<30 where !controller.acceptsClicks { await IslandVerification.pause(0.05) }
        IslandVerification.require(controller.backdropVisible && controller.outlineBounds.width > 0, "the rest pill is drawn")
        let others = backdrops.filter { $0.key != restID }.map(\.value)
        IslandVerification.require(others.count == 1 && others.allSatisfy { !$0.backdropVisible && !$0.showsRest },
                                   "the other display shows no pill")
        await controller.capture("dual-rest")
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.captured.contains("dual-rest"), "still taken of the resting display")

        await screensChanged(core, [screens[1]])
        let left = core.island.backdropControllers
        IslandVerification.require(Set(left.keys) == [ids[1]] && core.island.resting === left[ids[1]],
                                   "unplugging the first display moves the rest pill to the other")
        await screensChanged(core, nil)
        IslandVerification.require(Set(core.island.backdropControllers.keys) == Set(ids)
                                   && core.island.backdropControllers.values.filter(\.showsRest).count == 1,
                                   "replugging restores two backdrops and one rest pill")

        let windows = NSApp.windows.filter(\.isVisible)
        IslandVerification.require(windows.allSatisfy { win in screens.contains { $0.frame.contains(win.frame) } },
                                   "all own windows on a test display")
        print("PASS scene dual-display")
        _exit(0)
    }

    private static func screensChanged(_ core: AppCore, _ screens: [NSScreen]?) async {
        IslandVerification.screens = screens
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        await IslandVerification.pause(0.3)
    }
}
#endif
