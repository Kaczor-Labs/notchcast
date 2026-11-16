#if DEBUG
import AppKit
import IslandCore

/// The pill under a simulated notch, under forced Reduce Motion, and with more status than fits.
@MainActor
enum IslandProfileScenes {
    static let names: Set = ["notch-profile", "reduce-motion", "status-overflow"]
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
        beside("notice")
        controller.capture("notch-notice")
        presenter.end(notice: "notch")
        await IslandVerification.pause(0.5)

        await overflow(controller: controller, presenter: presenter, count: 3)
        beside("status")
        controller.capture("notch-status")
        await IslandVerification.pause(0.2)

        presenter.previewExpansion(seconds: 0.8)
        IslandMeetingScenes.preview(core)
        await IslandVerification.pause(0.6)
        let open = controller.outlineBounds
        print("NOTCH expanded bounds=\(open) key=\(controller.contentKey ?? "-")")
        IslandVerification.require(controller.contentKey == "expansion" && open.height > rest.height + 20
                                   && open.width > notch.width, "the expansion opens below and around the notch")
        controller.capture("notch-expanded")
        await IslandVerification.pause(1.4)
        IslandVerification.require(controller.contentKey == "glance", "the expansion settles to the glance")
        beside("glance")
        controller.capture("notch-glance")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured == ["notch-notice", "notch-status", "notch-expanded", "notch-glance"],
                                   "notice, status, expansion and glance captured")
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
        IslandVerification.require((1..<count).contains(controller.shownStatuses), "the oldest status drops from \(count)")
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

    /// Widest outline height and width seen while a change animates, beside the size it lands at.
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
