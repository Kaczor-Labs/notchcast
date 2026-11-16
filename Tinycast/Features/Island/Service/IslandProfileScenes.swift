#if DEBUG
import AppKit
import IslandCore

/// The pill under a simulated notch, under forced Reduce Motion, and with more status than fits.
@MainActor
enum IslandProfileScenes {
    static let names: Set = ["notch-profile", "reduce-motion", "status-overflow", "full-screen",
                              "full-screen-space"]
    private static var presenter: IslandPresenter? { AppCore.shared.islandPresenter as? IslandPresenter }
    private static var now: Double { ProcessInfo.processInfo.systemUptime }
    private static let notch = CGSize(width: 185, height: 32)

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        IslandController.simulatedNotch = scene == "notch-profile" ? notch : nil
        core.island.start()
        await IslandVerification.pause(0.4)
        guard let controller = core.island.resting, let presenter else {
            IslandVerification.require(false, "resting pill and presenter"); return
        }
        await settle(controller)
        IslandVerification.require(screen.frame.contains(controller.backdropWindow.frame), "pill on test display")
        switch scene {
        case "notch-profile": await notchProfile(core: core, controller: controller, presenter: presenter)
        case "reduce-motion": await reduceMotion(core: core, controller: controller, presenter: presenter)
        case "full-screen": await fullScreen(core: core, controller: controller, presenter: presenter)
        case "full-screen-space": await fullScreenSpace(screen: screen, controller: controller, presenter: presenter)
        default: await overflow(controller: controller, presenter: presenter, count: 6)
        }
        IslandScenes.pass(scene, screen: screen)
        _exit(0)
    }

    private static func settle(_ controller: IslandController) async {
        for _ in 0..<30 where !controller.acceptsClicks { await IslandVerification.pause(0.05) }
    }

    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.5 }

    private static func status(_ index: Int) -> IslandStatus {
        IslandStatus(id: "status-\(index)", symbol: "arrow.triangle.2.circlepath", text: "Sync", label: "Sync \(index)")
    }

    private static func notchProfile(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        let rest = controller.outlineBounds
        print("NOTCH rest=\(rest)")
        IslandVerification.require(near(rest.width, notch.width) && near(rest.height, notch.height * 2),
                                   "the resting pill is the notch")
        func beside(_ state: String) {
            let bounds = controller.outlineBounds
            print("NOTCH \(state) bounds=\(bounds) target=\(controller.glanceWidthTarget)")
            IslandVerification.require(near(bounds.width, controller.glanceWidthTarget) && bounds.width > notch.width + 8,
                                       "\(state) sits in wings beside the notch")
            IslandVerification.require(bounds.minX <= rest.minX + 0.5 && bounds.maxX >= rest.maxX - 0.5,
                                       "\(state) keeps the notch covered")
        }
        presenter.post(IslandNotice(id: "notch", symbol: "doc.on.doc", text: "Copied", seconds: 3), onTap: nil)
        await IslandVerification.pause(0.6)
        let line = controller.outlineBounds
        print("NOTCH notice bounds=\(line) key=\(controller.contentKey ?? "-")")
        IslandVerification.require(controller.contentKey == "notice.notch" && controller.showsHeadline
            && line.minY < rest.minY - 20 && line.maxY >= rest.maxY - 0.5 && line.minX <= rest.minX + 0.5
            && line.maxX >= rest.maxX - 0.5, "a text notice opens below and around the notch")
        await controller.capture("notch-notice")
        presenter.end(notice: "notch")
        await IslandVerification.pause(0.5)

        presenter.post(IslandNotice(id: "notch-title", symbol: "arrow.down.circle", text: "Guide.pdf",
                                    progress: IslandProgress(fraction: 0.2)), onTap: nil)
        await IslandVerification.pause(0.6)
        IslandVerification.require(controller.showsHeadline, "a titled progress opens with its title below the notch")
        await IslandVerification.pause(IslandNotice.messageSeconds)
        IslandVerification.require(!controller.showsHeadline, "a titled progress settles to the wings after one dwell")
        beside("titled progress")
        presenter.end(notice: "notch-title")
        await IslandVerification.pause(0.5)

        presenter.post(IslandNotice(id: "notch-ring", symbol: "arrow.down.circle", text: "Downloading…",
                                    progress: IslandProgress(fraction: 0.4, headline: false)), onTap: nil)
        await IslandVerification.pause(0.6)
        beside("progress")
        await controller.capture("notch-progress")
        presenter.end(notice: "notch-ring")
        await IslandVerification.pause(0.5)

        await overflow(controller: controller, presenter: presenter, count: 3)
        beside("status")
        await controller.capture("notch-status")
        await IslandVerification.pause(0.2)

        presenter.previewExpansion(seconds: 0.8)
        IslandMeetingScenes.preview(core)
        await IslandVerification.pause(0.6)
        let open = controller.outlineBounds
        print("NOTCH expanded bounds=\(open) key=\(controller.contentKey ?? "-")")
        IslandVerification.require(controller.contentKey == "expansion" && open.minY < rest.minY - 20
            && open.maxY >= rest.maxY - 0.5 && open.minX <= rest.minX + 0.5 && open.maxX >= rest.maxX - 0.5,
            "the expansion opens below and around the notch")
        await controller.capture("notch-expanded")
        await IslandVerification.pause(1.4)
        IslandVerification.require(controller.contentKey == "glance", "the expansion settles to the glance")
        beside("glance")
        await controller.capture("notch-glance")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["notch-notice", "notch-progress", "notch-status", "notch-expanded",
                                   "notch-glance"], "notice, progress, status, expansion and glance captured")
    }

    /// Statuses past the wing drop oldest first; the newest stays drawn and still takes the tap.
    private static func overflow(controller: IslandController, presenter: IslandPresenter, count: Int) async {
        var tapped: String?
        for index in 0..<count {
            presenter.setStatus(status(index), for: "status-\(index)", onTap: { tapped = "status-\(index)" })
        }
        await IslandVerification.pause(0.4)
        await settle(controller)
        print("OVERFLOW count=\(count) shown=\(controller.shownStatuses) bounds=\(controller.outlineBounds)")
        IslandVerification.require(controller.statuses.count == count, "the pill holds all \(count) statuses")
        let shown = controller.shownStatuses
        IslandVerification.require((1..<count).contains(shown.count)
            && shown == (count - shown.count..<count).map { "status-\($0)" }, "the oldest statuses drop from \(count)")
        IslandVerification.require(controller.pressBackdrop() && tapped == "status-\(count - 1)", "a tap acts on the newest")
        presenter.setStatus(nil, for: "status-\(count - 1)", onTap: nil)
        await IslandVerification.pause(0.4)
        await settle(controller)
        IslandVerification.require(controller.pressBackdrop() && tapped == "status-\(count - 2)",
                                   "with the newest gone, a tap acts on the next newest")
        presenter.setStatus(status(count - 1), for: "status-\(count - 1)", onTap: { tapped = "status-\(count - 1)" })
        await IslandVerification.pause(0.4)
        await settle(controller)
    }

    /// On a full-screen Space the pill hides at rest; each glance shows and hides once it settles.
    private static func fullScreen(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        func expect(_ shown: Bool, _ state: String) {
            print("FULLSCREEN \(state) visible=\(controller.backdropVisible) key=\(controller.contentKey ?? "-")")
            IslandVerification.require(controller.backdropVisible == shown, "\(state) \(shown ? "shows" : "hides")")
        }
        func hidden(_ state: String) async {
            for _ in 0..<40 where controller.backdropVisible { await IslandVerification.pause(0.05) }
            expect(false, state)
        }
        expect(true, "the resting pill on a desktop")
        controller.onFullScreenSpace = true
        expect(false, "the resting pill on a full-screen Space")
        presenter.post(IslandNotice(id: "full", symbol: "doc.on.doc", text: "Copied", seconds: 3), onTap: nil)
        expect(true, "a notice")
        presenter.end(notice: "full")
        await hidden("the pill after the notice")
        presenter.showLevel(VolumeLevel.island(0.6, muted: false))
        expect(true, "a volume level")
        await IslandVerification.pause(0.3)
        await hidden("the pill after the level")
        presenter.setStatus(status(0), for: "status-0", onTap: nil)
        await IslandVerification.pause(0.5)
        expect(false, "a status")
        presenter.setStatus(nil, for: "status-0", onTap: nil)
        presenter.previewExpansion(seconds: 0.6)
        IslandMeetingScenes.preview(core)
        expect(true, "the meeting expansion")
        await IslandVerification.pause(0.3)
        await hidden("the meeting glance")
        IslandVerification.require(controller.contentKey == "glance", "the expansion settled to the glance")
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.4)
        expect(true, "the palette")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await hidden("the pill after the palette")
        controller.onFullScreenSpace = false
        expect(true, "the meeting glance back on a desktop")
    }

    /// A real full-screen Space hides the rest pill, a zoomed window anywhere else does not.
    private static func fullScreenSpace(screen: NSScreen, controller: IslandController,
                                        presenter: IslandPresenter) async {
        func window(_ frame: CGRect) -> NSWindow {
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered,
                                  defer: false)
            window.isReleasedWhenClosed = false
            window.setFrame(frame, display: false)
            window.makeKeyAndOrderFront(nil)
            return window
        }
        let zoomed = window(screen.visibleFrame)
        await IslandVerification.pause(0.3)
        AppCore.shared.island.spaceChanged()
        await IslandVerification.pause(0.5)
        IslandVerification.require(controller.backdropVisible && !controller.onFullScreenSpace,
                                   "a zoomed window keeps the rest pill")
        let full = window(screen.frame.insetBy(dx: 200, dy: 200))
        full.collectionBehavior = .fullScreenPrimary
        await IslandVerification.pause(0.3)
        full.toggleFullScreen(nil)
        for _ in 0..<60 where !full.styleMask.contains(.fullScreen) { await IslandVerification.pause(0.05) }
        await IslandVerification.pause(0.5)
        let trusted = Permissions.isAccessibilityTrusted()
        for _ in 0..<60 where controller.onFullScreenSpace != trusted { await IslandVerification.pause(0.05) }
        print("SPACE full=\(full.styleMask.contains(.fullScreen)) trusted=\(trusted) "
              + "space=\(controller.onFullScreenSpace) visible=\(controller.backdropVisible)")
        IslandVerification.require(full.styleMask.contains(.fullScreen) && !zoomed.isOnActiveSpace,
                                   "the window enters its own full-screen Space")
        IslandVerification.require(controller.onFullScreenSpace == trusted && controller.backdropVisible == !trusted,
                                   trusted ? "the rest pill hides on the Space" : "with no AX grant the rest pill stays")
        presenter.post(IslandNotice(id: "space", symbol: "doc.on.doc", text: "Copied", seconds: 3), onTap: nil)
        await IslandVerification.pause(0.4)
        IslandVerification.require(controller.backdropVisible && controller.backdropWindow.isOnActiveSpace,
                                   "a notice shows on the full-screen Space")
        presenter.end(notice: "space")
        for _ in 0..<40 where controller.backdropVisible == trusted { await IslandVerification.pause(0.05) }
        IslandVerification.require(controller.backdropVisible == !trusted, "the pill settles back after the notice")
        zoomed.makeKeyAndOrderFront(nil)
        for _ in 0..<60 where !zoomed.isOnActiveSpace || controller.onFullScreenSpace {
            await IslandVerification.pause(0.05)
        }
        IslandVerification.require(zoomed.isOnActiveSpace && !full.isOnActiveSpace && !controller.onFullScreenSpace
            && controller.backdropVisible, "back on the desktop a zoomed window of the same app keeps the pill")
    }

    private static func track(_ controller: IslandController, for seconds: Double) async -> (peak: CGSize, end: CGSize) {
        var peak = CGSize.zero
        let start = now
        while now < start + seconds {
            let bounds = controller.outlineBounds
            peak = CGSize(width: max(peak.width, bounds.width), height: max(peak.height, bounds.height))
            await IslandVerification.pause(1.0 / 240)
        }
        return (peak, controller.outlineBounds.size)
    }

    /// The spring overshoots the level's width; `.always` lands both changes with no overshoot.
    private static func reduceMotion(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        func level(_ setting: ReducedMotionSetting) async -> (peak: CGSize, end: CGSize) {
            controller.motion = setting
            IslandVerification.require(controller.reduced == (setting == .always), "\(setting) sets the surface")
            presenter.showLevel(VolumeLevel.island(0.6, muted: false))
            let level = await track(controller, for: 0.5)
            print("MOTION \(setting) level peak=\(level.peak) end=\(level.end)")
            return level
        }
        let spring = await level(.never)
        IslandVerification.require(spring.peak.width > spring.end.width + 1, "the control spring overshoots the level")
        await IslandVerification.pause(1.4)
        let reduced = await level(.always)
        IslandVerification.require(reduced.peak.width <= reduced.end.width + 0.5 && reduced.end.width > 100,
                                   "Reduce Motion lands the level with no spring")
        await IslandVerification.pause(1.5)
        presenter.previewExpansion(seconds: 1.2)
        IslandMeetingScenes.preview(core)
        let open = await track(controller, for: 0.7)
        print("MOTION always expansion peak=\(open.peak) end=\(open.end) key=\(controller.contentKey ?? "-")")
        IslandVerification.require(controller.contentKey == "expansion" && open.end.height > 40,
                                   "the expansion opens under Reduce Motion")
        IslandVerification.require(open.peak.width <= open.end.width + 0.5 && open.peak.height <= open.end.height + 0.5,
                                   "Reduce Motion opens the expansion with no spring")
    }
}
#endif
