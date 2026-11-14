#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum IslandOverlayScenes {
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
        controller.capture("question")
        await IslandVerification.pause(0.2)
        let second = await core.confirm(title: "Second question", message: nil, symbol: nil, confirmTitle: "Continue")
        IslandVerification.require(!second && core.isShowingDialog, "second question cancels immediately without closing first")
        core.showProgress("Synthetic progress report")
        await IslandVerification.pause(0.3)
        controller.capture("report-with-question")
        await IslandVerification.pause(0.2)
        let reports = NSApp.windows.filter { $0 is HUDPanel && $0.isVisible }
        IslandVerification.require(reports.count == 1, "one stock progress HUD")
        IslandVerification.require(reports.allSatisfy { !$0.frame.intersects(question.frame) }, "report never covers question")
        IslandVerification.require(question.isKeyWindow && core.isShowingDialog && panel.isVisible,
                                   "report preserves question key, flag and open palette")
        let report = reports.first
        core.showMessage("Synthetic completed report")
        await IslandVerification.pause(0.1)
        let replacement = NSApp.windows.first { $0 is HUDPanel && $0.isVisible }
        IslandVerification.require(report?.isVisible == true && replacement === report,
                                   "progress replaced on existing native HUD")
        IslandLatency.key(question, code: 53, characters: "\u{1b}")
        IslandVerification.require(await answer == false && !core.isShowingDialog, "Escape cancels native question")
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
        core.island.active?.capture("report")
        await IslandVerification.pause(0.3)
        IslandVerification.require(first?.isVisible == true && panel.isKeyWindow, "replacement preserves palette first responder")
        await IslandVerification.pause(1.3)
        presenter.extend()
        await IslandVerification.pause(1.2)
        IslandVerification.require(presenter.isShowing, "extend survives original 2.4 second deadline")
        await IslandVerification.pause(1.5)
        IslandVerification.require(!presenter.isShowing, "extended dwell ends after 2.4 seconds and fade")
        core.island.active?.capture("report-ended")
        await IslandVerification.pause(0.3)
        print("PASS island HUD isShowing, progress replacement, extend and 2.4 second dwell")
        _exit(0)
    }
}
#endif
