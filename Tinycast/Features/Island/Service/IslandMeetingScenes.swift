#if DEBUG
import AppKit

/// The carded meeting's expansion, with a shorter dwell so each scene fits the 9 s run.
@MainActor
enum IslandMeetingScenes {
    static let names: Set = ["meeting-expand", "meeting-expand-level", "meeting-expand-palette", "meeting-expand-rebuild"]
    private static var presenter: IslandPresenter? { AppCore.shared.islandPresenter as? IslandPresenter }
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private static func until(_ time: Double) async { await IslandVerification.pause(max(0, time - now)) }

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        core.island.start()
        await IslandVerification.pause(0.1)
        guard let controller = core.island.resting, let presenter else {
            IslandVerification.require(false, "resting pill and presenter"); return
        }
        print("MEETING_READY \(scene) at \(Date().formatted(.dateTime.hour().minute().second()))")
        switch scene {
        case "meeting-expand": await expand(core: core, controller: controller, presenter: presenter)
        case "meeting-expand-level": await level(core: core, controller: controller, presenter: presenter)
        case "meeting-expand-rebuild": await rebuild(core: core, controller: controller, presenter: presenter)
        default: await palette(core: core, controller: controller, presenter: presenter)
        }
        IslandScenes.pass(scene, screen: screen)
        _exit(0)
    }

    static func preview(_ core: AppCore, expands: Bool = true) {
        let date = Date()
        let meeting = MeetingEvent(id: "meeting", title: "Weekly product sync", start: date + 4 * 60,
            end: date + 34 * 60, isAllDay: false, isDeclined: false, calendarID: "c", calendarName: "Work",
            calendarColor: nil, calendarItemID: "i", link: MeetingLink.detect(in: "https://us02web.zoom.us/j/123456789"))
        core.island.glance.preview(meeting, now: date, expands: expands)
    }

    private static func expand(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        presenter.previewExpansion(seconds: 0.8)
        let rest = controller.outlineBounds
        let start = now
        preview(core)
        await IslandVerification.pause(0.6)
        print("EXPANDED rest=\(rest) bounds=\(controller.outlineBounds) key=\(controller.contentKey ?? "-")")
        IslandVerification.require(controller.contentKey == "expansion" && presenter.expansions == 1,
                                   "the window opening expands the pill once")
        IslandVerification.require(controller.outlineBounds.height > rest.height + 20, "the pill grows to two lines")
        await controller.capture("meeting-expanded")
        await until(start + 0.9)
        IslandVerification.require(controller.contentKey == "glance" && !controller.expanded, "it settles to the glance")
        func settled() -> Bool {
            abs(controller.outlineBounds.width - controller.glanceWidthTarget) < 0.01
                && abs(controller.outlineBounds.height - rest.height) < 0.01
        }
        while !settled(), now < start + 2.2 { await IslandVerification.pause(0.05) }
        print("SETTLED after=\(now - start)s bounds=\(controller.outlineBounds) target=\(controller.glanceWidthTarget)")
        IslandVerification.require(settled(), "at the glance's size within 1.4 s of the settle")
        await controller.capture("meeting-settled")
        await IslandVerification.pause(5)
        IslandVerification.require(controller.contentKey == "glance" && presenter.expansions == 1, "no second expansion")
        await controller.capture("meeting-settled-later")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["meeting-expanded", "meeting-settled", "meeting-settled-later"],
                                   "expanded, settled and later captured")
        let stills = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"] ?? ""
        IslandVerification.require(FileManager.default.contentsEqual(atPath: stills + "/meeting-settled.png",
            andPath: stills + "/meeting-settled-later.png"), "the settled glance is unchanged 5 s later")
    }

    /// A level first makes the expansion wait, then a second level cuts it short with no replay.
    private static func level(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        presenter.previewExpansion(seconds: 3)
        presenter.showLevel(VolumeLevel.island(0.6, muted: false))
        let first = now
        await IslandVerification.pause(0.2)
        preview(core)
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.level != nil && presenter.expansions == 0, "the expansion waits for the level")
        await until(first + 2.1)
        IslandVerification.require(controller.contentKey == "expansion" && presenter.expansions == 1,
                                   "it expands once the level ends")
        await controller.capture("meeting-after-level")
        await IslandVerification.pause(0.2)
        presenter.showLevel(VolumeLevel.island(0.7, muted: false))
        let second = now
        await IslandVerification.pause(0.5)
        IslandVerification.require(controller.contentKey == "glance" && controller.level != nil && !controller.expanded,
                                   "a level cuts the expansion short")
        await controller.capture("meeting-cut-level")
        await until(second + 2.1)
        IslandVerification.require(controller.level == nil && controller.contentKey == "glance", "back at the glance")
        await IslandVerification.pause(0.8)
        IslandVerification.require(controller.contentKey == "glance" && presenter.expansions == 1,
                                   "a cut expansion never replays")
        await controller.capture("meeting-cut-after")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["meeting-after-level", "meeting-cut-level", "meeting-cut-after"],
                                   "waiting, cut and after captured")
    }

    /// Unplugging and replugging the display hands a live expansion to the new pill, with no replay.
    private static func rebuild(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        func screensChanged(_ screens: [NSScreen]?) async {
            IslandVerification.screens = screens
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await IslandVerification.pause(0.2)
        }
        presenter.previewExpansion(seconds: 2)
        let start = now
        preview(core)
        await IslandVerification.pause(0.4)
        IslandVerification.require(controller.contentKey == "expansion" && presenter.expansions == 1, "the pill expands")
        await screensChanged([])
        IslandVerification.require(!controller.expanded, "the unplugged pill drops the expansion")
        await screensChanged(nil)
        guard let next = core.island.resting, next !== controller else {
            IslandVerification.require(false, "the replug builds a new resting pill"); return
        }
        print("REBUILT key=\(next.contentKey ?? "-") expanded=\(next.expanded) glance=\(next.glance != nil)")
        IslandVerification.require(next.glance != nil && next.expanded && next.contentKey == "expansion"
            && presenter.expansions == 1, "the new pill keeps the expansion")
        await next.capture("meeting-rebuilt")
        await until(start + 2.3)
        IslandVerification.require(next.contentKey == "glance" && !next.expanded, "it settles at the original deadline")
        await screensChanged(nil)
        IslandVerification.require(core.island.resting?.contentKey == "glance" && presenter.expansions == 1,
                                   "a rebuild after the settle never replays")
        IslandVerification.require(next.captured == ["meeting-rebuilt"], "rebuilt pill captured")
    }

    private static func palette(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        presenter.previewExpansion(seconds: 1)
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.5)
        IslandVerification.panel = NSApp.windows.first { $0 is PalettePanel } as? PalettePanel
        IslandVerification.require(core.palette.isVisible, "the palette is open")
        preview(core)
        await IslandVerification.pause(0.3)
        IslandVerification.require(presenter.expansions == 0 && controller.contentKey == "palette", "the palette covers it")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(1.2)
        IslandVerification.require(controller.contentKey == "glance" && presenter.expansions == 0,
                                   "closing the palette shows the glance with no expansion")
        await controller.capture("meeting-palette-closed")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["meeting-palette-closed"], "glance captured")
    }
}
#endif
