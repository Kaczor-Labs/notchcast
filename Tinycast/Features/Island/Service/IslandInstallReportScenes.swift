#if DEBUG
import AppKit

/// `install-report`: the launch's install report on the pill; one that did not install asks Try Again.
@MainActor
enum IslandInstallReportScenes {
    static func run(core: AppCore, controller: IslandController) async {
        let activity = core.island.update
        guard let version = AppVersion("9.9.9") else { IslandVerification.require(false, "preview version"); return }
        activity.preview(nil, seconds: 0.6)
        activity.report(.installed(version))
        let installed = String(localized: "Updated to \(version.description)", table: "Notchcast")
        print("REPORT installed notice=\(controller.notice?.text ?? "nil") symbol=\(controller.notice?.symbol ?? "nil")")
        IslandVerification.require(controller.notice?.text == installed && controller.notice?.isFailure == false
            && controller.notice?.symbol == "checkmark.circle", "an installed version shows on the pill")
        await IslandVerification.pause(0.3)
        await controller.capture("install-report-installed")
        await IslandVerification.pause(0.6)
        IslandVerification.require(controller.notice == nil, "the installed notice runs out its dwell")

        activity.preview(nil, seconds: 4)
        activity.report(.notInstalled(version))
        print("REPORT not-installed notice=\(controller.notice?.text ?? "nil")")
        IslandVerification.require(controller.notice?.text == String(localized: "Update failed")
            && controller.notice?.isFailure == true, "a version that did not install shows a failure notice")
        for _ in 0..<20 where !controller.acceptsClicks { await IslandVerification.pause(0.05) }
        IslandVerification.require(controller.noticeTone === IslandNoticeArt.failureTone(frosted: controller.canvas.look == .frosted), "a failure glyph is red")
        await controller.capture("install-report-failed")
        IslandVerification.require(controller.pressBackdrop(), "the pill takes the tap")
        await IslandVerification.pause(0.3)
        let question = core.shownDialog
        print("REPORT question title=\(question?.title ?? "nil") actions=\(question?.actions.map(\.title) ?? [])")
        IslandVerification.require(question?.title == String(localized: "Update failed")
            && question?.actions.last?.title == String(localized: "Try Again")
            && question?.defaultIndex == question.map { $0.actions.count - 1 } && !IslandPillScenes.paletteVisible,
            "a tap on the failure notice asks Try Again, the default, and leaves the launcher closed")
        guard let panel = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) as? DialogPanel else {
            IslandVerification.require(false, "the Try Again question is on screen"); return
        }
        await controller.capture("install-report-try-again")
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.3)
        IslandVerification.require(core.shownDialog == nil && core.updateCoordinator.stage == .idle
            && question.map { core.lastDialogAnswer == $0.cancelIndex } == true,
            "Esc answers OK, closes the question and starts no check")
        core.islandPresenter.end(notice: IslandLiveState.id)
        activity.preview(nil)
    }
}
#endif
