#if DEBUG
import AppKit

@MainActor
enum IslandLevelScenes {
    static func run(core: AppCore, panel: PalettePanel) async {
        guard let controller = core.island.active else {
            IslandVerification.require(false, "level scene island"); return
        }
        for mode in [PaletteMode.launcher, .clipboard] {
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await IslandVerification.pause(0.1)
            core.paletteCoordinator.showPalette(mode: .launcher)
            await check("summon-\(mode)", panel: panel)
            core.paletteCoordinator.showPalette(mode: mode)
            await check("mode-\(mode)", panel: panel)
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.5)
        IslandVerification.require(controller.backdropWindow.isVisible, "rest visible after close")
        print("PASS island synchronous level and stable frame on every observed runloop pass")
        _exit(0)
    }

    private static func check(_ name: String, panel: PalettePanel) async {
        let probe = PassProbe(name: name, panel: panel)
        probe.sample()
        probe.start()
        await IslandVerification.pause(0.15)
        probe.stop()
        IslandVerification.require(probe.count > 1, "runloop samples \(name) count=\(probe.count)")
    }

    @MainActor
    private final class PassProbe: NSObject {
        let name: String
        let panel: PalettePanel
        let frame: CGRect
        private(set) var count = 0
        private var observer: CFRunLoopObserver?

        init(name: String, panel: PalettePanel) {
            self.name = name
            self.panel = panel
            frame = panel.frame
        }

        func start() {
            let activity = CFRunLoopActivity.beforeWaiting.rawValue
            observer = CFRunLoopObserverCreateWithHandler(nil, activity, true, 0) { [weak self] _, _ in
                self?.sample()
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        func stop() {
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observer = nil
        }

        func sample() {
            print("RUNLOOP \(name) pass=\(count) level=\(panel.level.rawValue) frame=\(panel.frame)")
            IslandVerification.require(panel.level.rawValue == 26 && panel.frame == frame,
                                       "level 26 and unchanged frame \(name) pass \(count)")
            count += 1
        }
    }
}
#endif
