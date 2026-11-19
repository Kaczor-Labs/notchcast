#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum IslandOverlayScenes {
    static func lifetime(core: AppCore, panel: PalettePanel) async {
        guard let controller = core.island.active else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(1.2)
        let rest = controller.outlineBounds
        async let answer = core.confirm(title: "Lifetime verification", message: nil, symbol: nil, confirmTitle: "Keep")
        await IslandVerification.pause(0.5)
        guard let question = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) else {
            IslandVerification.require(false, "lifetime question visible"); return
        }
        await controller.capture("lifetime-question")
        IslandVerification.require(controller.outlineBounds.height > rest.height, "question grows resting island")
        IslandVerification.require(controller.canvas.glass == .sheet, "a question on the closed island is sheet glass")
        IslandLatency.key(question, code: 53, characters: "\u{1b}")
        IslandVerification.require(await answer == false, "lifetime question cancelled")
        await IslandVerification.pause(1.2)
        print("LIFETIME question rest=\(rest) actual=\(controller.outlineBounds)"
            + " overlays=\(controller.overlayCount) paletteVisible=\(panel.isVisible)")
        IslandVerification.require(controller.overlayCount == 0 && abs(controller.outlineBounds.height - rest.height) < 0.1,
                                   "question orderOut contracts island to rest")
        IslandVerification.require(controller.canvas.glass == .bar, "the island at rest is bar glass again")
        let presenter = HUDPresenter(anchor: .edgeInset(24), dwell: 0.4, screen: { panel.screen })
        presenter.show(MessageHUDView(message: "Lifetime report", accessory: .progress))
        await IslandVerification.pause(0.3)
        await controller.capture("lifetime-report")
        IslandVerification.require(controller.outlineBounds.height > rest.height, "report grows resting island")
        IslandVerification.require(controller.canvas.glass == .pane, "a report on the closed island is pane glass")
        await IslandVerification.pause(1.4)
        print("LIFETIME report rest=\(rest) actual=\(controller.outlineBounds)"
            + " overlays=\(controller.overlayCount) paletteVisible=\(panel.isVisible)")
        IslandVerification.require(!presenter.isShowing && controller.overlayCount == 0
                                   && abs(controller.outlineBounds.height - rest.height) < 0.1,
                                   "HUD fade contracts island to rest")
        IslandVerification.require(controller.canvas.glass == .bar, "the island is bar glass once the report is gone")
        await controller.capture("lifetime-rest")
        await IslandVerification.pause(0.2)
        let closing = HUDPanel()
        closing.setContentSize(CGSize(width: 200, height: 60))
        core.island.overlays.placeReport(closing, screen: panel.screen)
        closing.orderFrontRegardless()
        closing.close()
        await IslandVerification.pause(0.8)
        IslandVerification.require(controller.overlayCount == 0
            && abs(controller.outlineBounds.height - rest.height) < 0.1, "native close releases overlay reservation")
        print("PASS island question and HUD orderOut release frames and contract outline to rest")
        _exit(0)
    }

    static func question(core: AppCore, panel: PalettePanel) async {
        async let answer = core.confirm(title: "Keep this change?",
            message: "Synthetic verification question.\nThe native dialog owns keyboard focus.",
            symbol: "questionmark.circle", confirmTitle: "Keep", tone: .neutral, confirmRole: .standard)
        await IslandVerification.pause(0.2)
        guard let question = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) as? DialogPanel,
              let controller = core.island.active else {
            IslandVerification.require(false, "native question visible"); return
        }
        IslandVerification.require(core.isShowingDialog && question.isKeyWindow, "question flag and native key window")
        await controller.capture("question")
        IslandVerification.require(controller.canvas.glass == .bar, "a question over the open launcher keeps bar glass")
        await IslandVerification.pause(0.2)
        let second = await core.confirm(title: "Second question", message: nil, symbol: nil, confirmTitle: "Continue")
        IslandVerification.require(!second && core.isShowingDialog, "second question cancels immediately without closing first")
        core.showProgress("Synthetic progress report")
        await IslandVerification.pause(0.3)
        await controller.capture("report-with-question")
        await IslandVerification.pause(0.2)
        let reports = NSApp.windows.filter { $0 is HUDPanel && $0.isVisible }
        IslandVerification.require(reports.count == 1, "one stock progress HUD")
        IslandVerification.require(controller.canvas.glass == .bar, "a report over the open launcher keeps bar glass")
        IslandVerification.require(reports.allSatisfy { !$0.frame.intersects(question.frame) }, "report never covers question")
        IslandVerification.require(question.isKeyWindow && core.isShowingDialog && panel.isVisible,
                                   "report preserves question key, flag and open palette")
        IslandVerification.require(!controller.pressBackdrop() && question.isKeyWindow && core.isShowingDialog,
                                   "question margin press cannot switch screen or cancel question")
        let report = reports.first
        core.showMessage("Synthetic completed report")
        await IslandVerification.pause(0.1)
        let replacement = NSApp.windows.first { $0 is HUDPanel && $0.isVisible }
        IslandVerification.require(report?.isVisible == true && replacement === report,
                                   "progress replaced on existing native HUD")
        IslandLatency.key(question, code: 53, characters: "\u{1b}")
        IslandVerification.require(await answer == false && !core.isShowingDialog, "Escape cancels native question")
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.overlayCount == 1, "question orderOut releases its island frame")
        async let volume = core.pickVolume(current: 0.5)
        await IslandVerification.pause(0.15)
        guard let slider = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) as? DialogPanel else {
            IslandVerification.require(false, "volume question visible"); return
        }
        IslandVerification.require(slider.handlesArrowKeys, "volume question retains arrow contract")
        IslandLatency.key(slider, code: 126, characters: "\u{f700}")
        IslandLatency.key(slider, code: 36, characters: "\r")
        let result = await volume
        IslandVerification.require((result ?? 0) > 0.5, "Up and Enter adjust and accept volume")
        async let edit = core.editClipboardText("Synthetic editable text")
        await IslandVerification.pause(0.2)
        guard let editor = NSApp.windows.first(where: { $0 is DialogPanel && $0.isVisible }) as? DialogPanel else {
            IslandVerification.require(false, "clipboard editor question visible"); return
        }
        IslandVerification.require(editor.acceptsLineBreaks && editor.frame.width > question.frame.width,
                                   "native text accessory keeps line breaks and wider size")
        IslandLatency.key(editor, code: 36, characters: "\r")
        await IslandVerification.pause(0.1)
        IslandVerification.require(editor.isVisible && core.isShowingDialog, "Return edits instead of accepting")
        IslandLatency.key(editor, code: 36, characters: "\r", modifiers: .command)
        let edited = await edit
        IslandVerification.require(edited?.contains("\n") == true, "native editor inserts line break and command Return saves")
        print("PASS island question priority, second-question cancel, progress replacement, volume keys and text accessory")
        _exit(0)
    }

    static func report(core: AppCore, panel: PalettePanel) async {
        let presenter = HUDPresenter(anchor: .edgeInset(24), dwell: 2.4, screen: { panel.screen })
        presenter.show(MessageHUDView(message: "Synthetic progress", accessory: .progress), dwells: false)
        await IslandVerification.pause(0.2)
        IslandVerification.require(presenter.isShowing, "progress isShowing")
        let first = NSApp.windows.first { $0 is HUDPanel && $0.isVisible }
        presenter.show(MessageHUDView(message: "Synthetic completed report", accessory: .tone(.success)))
        await core.island.active?.capture("report")
        await IslandVerification.pause(0.3)
        IslandVerification.require(first?.isVisible == true && panel.isKeyWindow, "replacement preserves palette first responder")
        await IslandVerification.pause(1.3)
        presenter.extend()
        await IslandVerification.pause(1.2)
        IslandVerification.require(presenter.isShowing, "extend survives original 2.4 second deadline")
        await IslandVerification.pause(1.5)
        IslandVerification.require(!presenter.isShowing, "extended dwell ends after 2.4 seconds and fade")
        IslandVerification.require(core.island.active?.overlayCount == 0, "HUD fade orderOut releases island frame")
        await core.island.active?.capture("report-ended")
        await IslandVerification.pause(0.3)
        let volume = HUDPresenter(anchor: .heightFraction(0.12), dwell: 1.6, screen: { panel.screen })
        volume.show(VolumeHUDView(state: VolumeState(level: 0.5)), size: CGSize(width: 200, height: 100))
        await IslandVerification.pause(0.2)
        if let screen = panel.screen, let hud = NSApp.windows.first(where: { $0 is HUDPanel && $0.isVisible }) {
            IslandVerification.require(abs(hud.frame.minY
                - (screen.visibleFrame.minY + screen.visibleFrame.height * 0.12)) < 0.01,
                                       "volume HUD retains stock bottom anchor")
            IslandVerification.require(core.island.active?.overlayCount == 0, "volume does not expand island")
        } else { IslandVerification.require(false, "volume HUD visible") }
        print("PASS island HUD isShowing, progress replacement, extend and 2.4 second dwell")
        _exit(0)
    }
}
#endif
