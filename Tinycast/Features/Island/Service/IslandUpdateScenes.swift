#if DEBUG
import AppKit

/// `update`: previews each install stage, never a download, and reads what the island says for it.
@MainActor
enum IslandUpdateScenes {
    static func run(core: AppCore, controller: IslandController) async {
        let activity = core.island.update
        let readable = !IslandAccessibilityScenes.otherClientRunning
        if !readable { print("NOT VERIFIED: other AX client") }
        /// The pill only takes a click once its spring from the notice to the status has settled.
        func settled() async {
            for _ in 0..<20 where !controller.acceptsClicks { await IslandVerification.pause(0.05) }
        }
        func read(_ state: String, _ value: String, covered: Bool = false) {
            let element = readable && !covered ? IslandAccessibilityScenes.islandElement(controller) : nil
            let read = element.flatMap { IslandAccessibilityScenes.attribute($0, kAXValueAttribute) }
            print("UPDATE \(state) value=\(read ?? "nil") notice=\(controller.notice?.text ?? "nil") "
                + "statuses=\(controller.statuses.map(\.label))")
            if readable, !covered { IslandVerification.require(read == value, "\(state): the AX value reads \"\(value)\"") }
            IslandVerification.require(controller.accessibilityValue == value, "\(state): the island says \"\(value)\"")
        }
        guard let version = AppVersion("9.9.9"), let asset = URL(string: "https://example.invalid/Notchcast.zip") else {
            IslandVerification.require(false, "preview release"); return
        }
        let release = AvailableRelease(version: version, tag: "v9.9.9", assetURL: asset, assetSize: 100,
                                       signatureURL: nil, publishedAt: nil)
        activity.preview(.available(release))
        read("available", "")
        IslandVerification.require(IslandVerification.announcements.isEmpty, "an automatic offer shows nothing")

        activity.preview(.installing(release, .downloading(received: 30, expected: 100)))
        read("downloading", String(localized: "Downloading…"))
        IslandVerification.require(controller.notice?.progress == 0.3 && controller.notice?.symbol == "arrow.down.circle",
                                   "the download notice carries received over expected")
        await IslandVerification.pause(0.4)
        await controller.capture("update-download")
        await IslandVerification.pause(0.2)
        activity.preview(.installing(release, .extracting))
        read("expanding", String(localized: "Expanding…"))
        IslandVerification.require(controller.notice?.progress == 1, "expanding holds progress at 1")

        let ready = String(localized: "Update ready")
        activity.preview(.readyToRelaunch)
        read("ready", ready)
        await IslandVerification.pause(2.1)
        IslandVerification.require(controller.notice?.text == ready, "the ready notice still shows at 2.1 s")
        await IslandVerification.pause(0.5)
        IslandVerification.require(controller.notice == nil, "the ready notice ends after 2.4 s")
        read("ready-status", ready)
        await controller.capture("update-ready")
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.captured.contains("update-ready"), "ready status capture")

        await settled()
        let heard = IslandVerification.announcements
        IslandVerification.require(controller.pressBackdrop() && IslandPillScenes.paletteVisible,
                                   "a tap on the ready status opens the palette")
        await IslandVerification.pause(0.4)
        read("palette", "", covered: true)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.4)
        read("palette-closed", ready)
        IslandVerification.require(IslandVerification.announcements == heard, "closing the palette replays no notice")

        let failed = String(localized: "Update failed")
        activity.preview(nil, seconds: 0.6)
        core.updateCoordinator.previewFailure(.downloadFailed("preview"))
        await IslandVerification.pause(0.1)
        read("failed", failed)
        IslandVerification.require(controller.notice?.isFailure == true, "the failed notice is a failure")
        IslandVerification.require(controller.noticeTone === IslandNoticeArt.failureTone, "a failure glyph is red")
        await IslandVerification.pause(0.4)
        await controller.capture("update-failed")
        await IslandVerification.pause(0.4)
        read("failed-status", failed)
        await settled()
        IslandVerification.require(controller.statuses.first?.symbol == "exclamationmark.arrow.circlepath",
                                   "the failed status offers a retry")
        _ = controller.pressBackdrop()
        await IslandVerification.pause(0.3)
        IslandVerification.require(!IslandPillScenes.paletteVisible, "a tap on the failed status leaves the palette closed")
        await tryAgain(core: core, controller: controller, title: failed)

        activity.preview(.available(release))
        read("cancelled", "")
        IslandVerification.require(controller.notice == nil && controller.statuses.isEmpty, "cancel clears notice and status")
        print("ANNOUNCED \(IslandVerification.announcements)")
        IslandVerification.require(IslandVerification.announcements == [String(localized: "Downloading…"),
            String(localized: "Expanding…"), ready, failed], "each stage announces once")
        core.updateCoordinator.dismiss()
        activity.preview(nil)
    }

    /// The real failed stage, so the tap runs `showFailure`; Esc declines, so nothing downloads.
    private static func tryAgain(core: AppCore, controller: IslandController, title: String) async {
        let question = core.shownDialog
        print("UPDATE question title=\(question?.title ?? "nil") actions=\(question?.actions.map(\.title) ?? [])")
        IslandVerification.require(question?.title == title
            && question?.actions.last?.title == String(localized: "Try Again")
            && question?.defaultIndex == question.map { $0.actions.count - 1 },
            "a tap on the failed status asks Try Again, the default")
        guard let panel = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) as? DialogPanel else {
            IslandVerification.require(false, "the Try Again question is on screen"); return
        }
        await controller.capture("update-try-again")
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.3)
        let stage = core.updateCoordinator.stage
        IslandVerification.require(core.shownDialog == nil && stage == .failed(.downloadFailed("preview")),
                                   "Esc closes the question and keeps the failure")
        print("UPDATE answer=\(core.lastDialogAnswer.map(String.init) ?? "nil") cancel=\(question?.cancelIndex ?? -1)")
        IslandVerification.require(question.map { core.lastDialogAnswer == $0.cancelIndex
            && $0.actions[$0.cancelIndex].title == String(localized: "OK") } == true,
            "Esc answers OK, not Try Again")
    }
}
#endif
