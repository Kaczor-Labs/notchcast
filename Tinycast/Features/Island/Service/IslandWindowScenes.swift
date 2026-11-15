#if DEBUG
import AppKit

@MainActor
enum IslandWindowScenes {
    static func run(core: AppCore, panel: PalettePanel) async {
        guard let controller = core.island.active, let screen = panel.screen else {
            IslandVerification.require(false, "window scene island and screen"); return
        }
        let backdrop = controller.backdropWindow
        IslandVerification.require(!controller.pressBackdrop(), "open backdrop cannot reopen launcher")
        let picker = PinnedOpenPanel()
        picker.testScreen = screen.frame
        picker.directoryURL = URL(filePath: ProcessInfo.processInfo.environment["ISLAND_OUTPUT"]!)
        picker.setFrame(CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 200,
                              width: 600, height: 400), display: false)
        let probe = ModalProbe {
            IslandVerification.require(NSApp.modalWindow === picker && picker.isVisible, "real open picker modal")
            IslandVerification.require(panel.level == .normal, "stock palette sinks during modal")
            IslandVerification.require(!backdrop.isVisible, "modal picker above hidden backdrop")
            IslandVerification.require(!controller.pressBackdrop(), "modal backdrop cannot reopen palette")
            print("MODAL picker=\(picker.frame) level=\(picker.level.rawValue)"
                + " palette=\(panel.level.rawValue) backdropVisible=\(backdrop.isVisible)")
            IslandVerification.require(screen.frame.contains(picker.frame), "picker stays on test display")
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            controller.closed()
            IslandVerification.require(!panel.isVisible && !backdrop.isVisible, "closed while modal suspended")
            picker.cancel(nil)
        }
        probe.perform(#selector(ModalProbe.check), with: nil, afterDelay: 0.5, inModes: [.modalPanel, .common])
        NSApp.activate()
        IslandVerification.require(picker.runModal() == .cancel, "modal cancelled in process")
        await IslandVerification.pause(0.3)
        IslandVerification.require(backdrop.isVisible && !panel.isVisible, "rest returns after modal ends with palette hidden")
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.6)
        IslandVerification.require(panel.level.rawValue == backdrop.level.rawValue + 1 && backdrop.isVisible,
                                   "summon restores island level after modal")
        IslandVerification.require(abs(panel.frame.maxY - screen.frame.maxY
            + IslandController.notch(on: screen).height) < 0.01, "restored palette touches island top")
        controller.capture("modal-return")
        let openPicker = PinnedOpenPanel()
        openPicker.testScreen = screen.frame
        openPicker.directoryURL = picker.directoryURL
        openPicker.setFrame(picker.frame, display: false)
        let openProbe = ModalProbe {
            IslandVerification.require(panel.isVisible && panel.level == .normal && !backdrop.isVisible,
                                       "open palette sinks under picker with backdrop hidden")
            openPicker.cancel(nil)
        }
        openProbe.perform(#selector(ModalProbe.check), with: nil, afterDelay: 0.5, inModes: [.modalPanel, .common])
        IslandVerification.require(openPicker.runModal() == .cancel, "open-palette modal cancelled in process")
        await IslandVerification.pause(0.3)
        print("OPEN_MODAL_RETURN palette=\(panel.level.rawValue) visible=\(panel.isVisible)"
            + " key=\(panel.isKeyWindow) backdropVisible=\(backdrop.isVisible)")
        IslandVerification.require(panel.isVisible && panel.level == IslandController.paletteLevel && backdrop.isVisible,
                                   "palette kept open through modal returns above backdrop")
        let frame = panel.frame
        let outline = controller.outlineBounds
        let surface = controller.surfaceIdentity
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        print("SCREEN_REBUILD frameBefore=\(frame) frameAfter=\(panel.frame)"
            + " outlineBefore=\(outline) outlineAfter=\(controller.outlineBounds)"
            + " sameController=\(core.island.active === controller)")
        IslandVerification.require(core.island.active === controller && panel.frame == frame
                                   && controller.surfaceIdentity == surface && controller.contentKey == "palette",
                                   "screen notification retains controller, native frame, surface and expanded presentation")
        core.paletteCoordinator.showPalette(mode: .clipboard)
        await IslandVerification.pause(0.2)
        IslandVerification.require(panel.level.rawValue == backdrop.level.rawValue + 1
            && abs(panel.frame.maxY - screen.frame.maxY + IslandController.notch(on: screen).height) < 0.01,
                                   "mode re-show restores level and top without a new key notification")
        IslandVerification.require(!controller.pressBackdrop() && core.palette.mode == .clipboard,
                                   "expanded backdrop preserves clipboard mode")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.6)
        let settings = NSWindow(contentRect: CGRect(x: screen.frame.midX - 200, y: screen.frame.midY - 150,
            width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        settings.title = "Settings verification"
        settings.makeKeyAndOrderFront(nil)
        let activation = NSRunningApplication.current.activate(options: [.activateAllWindows])
        await IslandVerification.pause(0.2)
        settings.makeKeyAndOrderFront(nil)
        print("SETTINGS activationRequest=\(activation) active=\(NSApp.isActive) key=\(settings.isKeyWindow)")
        if !NSApp.isActive || !settings.isKeyWindow {
            print("NOT VERIFIED real Settings activation/deactivation; macOS rejected activation request")
        }
        NSApp.deactivate()
        await IslandVerification.pause(0.3)
        IslandVerification.require(!NSApp.isActive && backdrop.isVisible && !backdrop.hidesOnDeactivate,
                                   "rest pill visible after deactivate call; hidesOnDeactivate false")
        settings.orderOut(nil)
        controller.capture("rest-deactivated")
        await IslandVerification.pause(0.2)
        IslandVerification.require(controller.pressBackdrop(), "rest pill opens launcher")
        await IslandVerification.pause(0.2)
        IslandVerification.require(panel.isVisible && core.palette.mode == .launcher, "rest press shows launcher")
        print("PASS island window modal, deterministic level restore, screen retention and rest-only clicks")
        _exit(0)
    }

    final class ModalProbe: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func check() { action() }
    }

    final class PinnedOpenPanel: NSOpenPanel {
        var testScreen: CGRect?
        override func center() {
            guard let testScreen else { return }
            setFrame(CGRect(x: testScreen.midX - frame.width / 2, y: testScreen.midY - frame.height / 2,
                            width: frame.width, height: frame.height), display: false)
        }
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            guard let testScreen else { return frameRect }
            let width = min(frameRect.width, testScreen.width)
            let height = min(frameRect.height, testScreen.height)
            return CGRect(x: min(max(frameRect.minX, testScreen.minX), testScreen.maxX - width),
                          y: min(max(frameRect.minY, testScreen.minY), testScreen.maxY - height),
                          width: width, height: height)
        }
        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            super.setFrame(constrainFrameRect(frameRect, to: nil), display: flag)
        }
    }
}
#endif
