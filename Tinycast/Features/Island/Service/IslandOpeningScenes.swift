#if DEBUG
import AppKit

@MainActor
enum IslandOpeningScenes {
    static let names: Set = ["expand-openings", "headline-cap"]
    private static var presenter: IslandPresenter? { AppCore.shared.islandPresenter as? IslandPresenter }
    private static var now: Double { CACurrentMediaTime() }
    private static let notch = CGSize(width: 185, height: 32)

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        IslandController.simulatedNotch = notch
        core.island.start()
        await IslandVerification.pause(0.2)
        guard let controller = core.island.resting, let presenter else {
            IslandVerification.require(false, "resting pill and presenter"); return
        }
        for _ in 0..<30 where !controller.acceptsClicks { await IslandVerification.pause(0.05) }
        if scene == "expand-openings" {
            await openings(core: core, controller: controller, presenter: presenter)
        } else {
            await cap(controller: controller, presenter: presenter)
        }
        IslandScenes.pass(scene, screen: screen)
        _exit(0)
    }

    /// Returns once the island has painted nothing new for a tenth of a second.
    private static func quiet(_ controller: IslandController) async {
        let start = now
        var count = -1
        while now < start + 1.5 {
            await IslandVerification.pause(0.1)
            if controller.trace.count == count { return }
            count = controller.trace.count
        }
    }

    private static func travel(_ from: CGRect, _ to: CGRect) -> Double {
        max(abs(to.width - from.width), abs(to.height - from.height), abs(to.minX - from.minX), abs(to.maxY - from.maxY))
    }

    private static func opening(_ name: String, controller: IslandController, key: String, _ act: () -> Void) async {
        let before = controller.outlineBounds
        let index = controller.trace.count
        let start = now
        act()
        for _ in 0..<20 where controller.contentKey != key { await IslandVerification.pause(0.05) }
        IslandVerification.require(controller.contentKey == key, "\(name) reaches \(key)")
        await quiet(controller)
        let frames = Array(controller.trace[index...])
        guard let last = frames.last else { IslandVerification.require(false, "\(name) painted frames"); return }
        for (position, frame) in frames.prefix(2).enumerated() {
            let milliseconds = String(format: "%.1f", (frame.time - start) * 1000)
            print("OPENING \(name) frame\(position) +\(milliseconds)ms bounds=\(frame.bounds)")
        }
        print("OPENING \(name) before=\(before) last=\(last.bounds) key=\(controller.contentKey ?? "-")")
        let total = travel(before, last.bounds)
        let jump = frames.first { travel(before, $0.bounds) > 0.01 }.map { travel(before, $0.bounds) } ?? total
        print("OPENING \(name) travel=\(total) firstChange=\(jump) frames=\(frames.count)")
        IslandVerification.require(total > 20, "\(name) changes the island")
        IslandVerification.require(jump < total / 2, "\(name) springs: its first changing frame covers under half the travel")
    }

    private static func openings(core: AppCore, controller: IslandController, presenter: IslandPresenter) async {
        presenter.previewExpansion(seconds: 3)
        IslandMeetingScenes.preview(core, expands: false)
        await quiet(controller)
        IslandVerification.require(controller.contentKey == "glance", "the meeting shows as the glance")
        await opening("glance->palette", controller: controller, key: "palette") { core.paletteCoordinator.showPalette(mode: .launcher) }
        IslandVerification.panel = NSApp.windows.first { $0 is PalettePanel } as? PalettePanel
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await quiet(controller)
        await opening("glance->meeting", controller: controller, key: "expansion") { IslandMeetingScenes.preview(core) }
        await opening("meeting->palette", controller: controller, key: "palette") { core.paletteCoordinator.showPalette(mode: .launcher) }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.island.glance.preview(nil, now: Date())
        await quiet(controller)
        await opening("notch->headline", controller: controller, key: "notice.opening") {
            presenter.post(IslandNotice(id: "opening", text: "Copied", seconds: 3), onTap: nil)
        }
        IslandVerification.require(controller.showsHeadline, "the notice opens as the headline below the notch")
    }

    private static func cap(controller: IslandController, presenter: IslandPresenter) async {
        let cap = NotchTheme.Size.islandHeadlineMaxWidth
        let inset = NotchTheme.Spacing.islandInset
        let long = String(repeating: "Quarterly planning review notes for the whole design team. ", count: 4).prefix(200)
        presenter.post(IslandNotice(id: "cap", text: String(long), seconds: 3), onTap: nil)
        await quiet(controller)
        guard let art = controller.headline else { IslandVerification.require(false, "the long notice is a headline"); return }
        print("CAP long chars=\(long.count) size=\(art.size) outline=\(controller.outlineBounds.size)")
        IslandVerification.require(art.size.width <= cap && art.size.height == 65,
                                   "the long headline wraps inside the cap")
        IslandVerification.require(art.fit.lines == 3 && art.fit.truncated, "the last visible line is truncated")
        IslandVerification.require(abs(controller.outlineBounds.width - art.size.width) < 0.5, "the outline fits the card")
        presenter.end(notice: "cap")
        await quiet(controller)
        presenter.post(IslandNotice(id: "short", text: "Guide.pdf saved to the Downloads folder", seconds: 3), onTap: nil)
        await quiet(controller)
        guard let short = controller.headline else {
            IslandVerification.require(false, "the short notice is a headline"); return
        }
        print("CAP short width=\(short.size.width) textWidth=\(short.textWidth) natural=\(short.text.size().width)")
        IslandVerification.require(short.textWidth == ceil(short.text.size().width), "the short title keeps its natural width")
        let floor = notch.width + Theme.Radius.panel * 2
        IslandVerification.require(short.textWidth + inset * 2 > floor, "the short title is wider than the notch floor")
        IslandVerification.require(abs(short.size.width - (short.textWidth + inset * 2)) < 0.5 && short.size.width < cap,
                                   "the short headline is its natural width plus insets, under the cap")
        IslandVerification.require(short.fit.lines == 1 && !short.fit.truncated, "the short title has no ellipsis")
    }
}
#endif
