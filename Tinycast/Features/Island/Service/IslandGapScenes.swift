#if DEBUG
import AppKit
import SwiftUI

// Verification-gap probes. Observations only: every check prints OBS-PASS/OBS-FAIL and the scene
// still exits 0, so one run reports all findings of its item.
@MainActor
enum IslandGapScenes {
    static var screen: NSScreen?

    static func observe(_ ok: Bool, _ message: String) {
        print((ok ? "OBS-PASS " : "OBS-FAIL ") + message)
    }

    static func dump(_ tag: String) {
        let ordered = NSApp.orderedWindows
        for window in NSApp.windows where window.isVisible {
            let order = ordered.firstIndex(of: window).map(String.init) ?? "-"
            let parent = window.parent.map { String(describing: type(of: $0)) } ?? "-"
            let onTest = screen.map { $0.frame.intersects(window.frame) } ?? false
            print("\(tag) WIN \(type(of: window)) level=\(window.level.rawValue) key=\(window.isKeyWindow)"
                + " main=\(window.isMainWindow) order=\(order) parent=\(parent) onTest=\(onTest) frame=\(window.frame)")
        }
        print("\(tag) STATE key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")"
            + " active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)")
    }

    static func run(_ scene: String, core: AppCore, panel: PalettePanel, screen: NSScreen) async {
        self.screen = screen
        switch scene {
        case "gap-nested-modals": await nestedModals(core: core, panel: panel)
        case "gap-settings": await settings(core: core, panel: panel)
        case "gap-ime": await ime(core: core, panel: panel)
        case "gap-motion": await motion(core: core, panel: panel)
        case "gap-collection": collection(core: core, panel: panel)
        case "gap-ax": await accessibility(core: core, panel: panel)
        case "gap-tooltip": await IslandTooltipProbe.run(core: core, panel: panel, screen: screen)
        default: print("unknown gap scene \(scene)")
        }
        print("DONE \(scene)")
        _exit(0)
    }

    // MARK: 1. palette -> action menu -> dialog

    private static func nestedModals(core: AppCore, panel: PalettePanel) async {
        IslandLatency.focus(panel)
        IslandLatency.key(panel, code: 40, characters: "k", modifiers: .command)
        await IslandVerification.pause(0.4)
        dump("A-menu-open")
        observe(core.palette.menuOpen, "menu open after command-K")
        let menu = NSApp.windows.first { $0 is MenuPanel && $0.isVisible }
        observe(menu?.isKeyWindow == true, "menu is key before dialog")
        let result = Box<Bool?>(nil)
        Task { @MainActor in result.value = await core.confirm(title: "Nested probe", message: "Synthetic nested question.",
            symbol: "questionmark.circle", confirmTitle: "Keep", tone: .neutral, confirmRole: .standard) }
        await IslandVerification.pause(0.5)
        dump("B-dialog-over-menu")
        let dialog = NSApp.windows.first { $0 is DialogPanel && $0.isVisible }
        observe(core.isShowingDialog && dialog != nil, "dialog presented over open menu")
        observe(dialog?.isKeyWindow == true, "dialog is key window")
        observe(panel.isVisible, "palette still visible after dialog over menu")
        observe(core.palette.menuOpen && menu?.isVisible == true, "menu still open/visible after dialog over menu")
        if let dialog, let panelLevel = Optional(panel.level) {
            observe(dialog.level > panelLevel, "dialog level \(dialog.level.rawValue) above palette \(panelLevel.rawValue)")
            if let menu { observe(dialog.level >= menu.level, "dialog level above/equal menu \(menu.level.rawValue)") }
            let ordered = NSApp.orderedWindows
            if let menu, let i = ordered.firstIndex(of: dialog), let j = ordered.firstIndex(of: menu), let k = ordered.firstIndex(of: panel) {
                observe(i < j && j < k, "order front-to-back dialog(\(i)) < menu(\(j)) < palette(\(k))")
            }
        }
        let qBefore = core.palette.query
        let mBefore = core.palette.menuQuery
        if let key = NSApp.keyWindow { IslandLatency.key(key, code: 6, characters: "z") }
        await IslandVerification.pause(0.1)
        observe(core.palette.query == qBefore && core.palette.menuQuery == mBefore,
                "typed key goes to dialog, not palette (query '\(core.palette.query)' menuQuery '\(core.palette.menuQuery)')")
        // Escape 1
        if let key = NSApp.keyWindow { IslandLatency.key(key, code: 53, characters: "\u{1b}") }
        await IslandVerification.pause(0.4)
        dump("C-after-escape-1")
        observe(result.value == false && !core.isShowingDialog, "Escape 1 cancels the dialog (result \(String(describing: result.value)))")
        observe(panel.isVisible, "palette visible after Escape 1")
        observe(core.palette.menuOpen, "menu still open after Escape 1 (ordered unwind)")
        // Escape 2
        if let key = NSApp.keyWindow { IslandLatency.key(key, code: 53, characters: "\u{1b}") }
        await IslandVerification.pause(0.4)
        dump("D-after-escape-2")
        observe(!core.palette.menuOpen && panel.isVisible, "Escape 2 closes menu, palette stays")
        observe(panel.isKeyWindow, "palette key after menu closed")
        // Escape 3
        if let key = NSApp.keyWindow { IslandLatency.key(key, code: 53, characters: "\u{1b}") }
        await IslandVerification.pause(0.4)
        dump("E-after-escape-3")
        observe(!panel.isVisible, "Escape 3 closes palette")
        let stray = NSApp.windows.filter { $0.isVisible && ($0 is DialogPanel || $0 is MenuPanel || $0 is PalettePanel) }
        observe(stray.isEmpty, "no orphaned dialog/menu/palette windows (\(stray.count))")
    }

    // MARK: 2. Settings activation and return

    private static func settings(core: AppCore, panel: PalettePanel) async {
        // Seed the autosaved frame inside the test display so the window never opens on a physical one.
        let f = screen!.frame
        let w: CGFloat = 900, h: CGFloat = 640
        let x = f.minX + 400, y = f.minY + 200
        let value = "\(Int(x)) \(Int(y)) \(Int(w)) \(Int(h)) \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))"
        UserDefaults.standard.set(value, forKey: "NSWindow Frame SettingsWindow")
        print("SEED frame=\(value)")
        dump("A-before")
        IslandLatency.focus(panel)
        for character in "Notchcast Settings" { IslandLatency.key(panel, code: 0, characters: String(character)) }
        await IslandVerification.pause(0.3)
        let selected = core.palette.query
        print("QUERY \(selected) selection=\(core.palette.selection)")
        IslandLatency.key(panel, code: 36, characters: "\r")
        await IslandVerification.pause(1.5)
        dump("B-after-enter")
        for w in NSApp.windows { print("ALLWIN \(type(of: w)) title='\(w.title)' visible=\(w.isVisible) mask=\(w.styleMask.rawValue) frame=\(w.frame)") }
        print("SETTINGS-FOCUS-EXISTING \(core.settingsCoordinator.focusExisting())")
        let window = NSApp.windows.first { $0.isVisible && $0.title.localizedCaseInsensitiveContains("settings") }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
        observe(window != nil, "a titled Settings window is visible (title '\(window?.title ?? "-")')")
        if let window {
            observe(window.isKeyWindow, "Settings window is key")
            observe(NSApp.isActive, "app active after Settings opened")
            observe(NSApp.activationPolicy() == .regular, "activation policy regular while Settings open")
            observe(screen!.frame.contains(window.frame), "Settings frame on test display \(window.frame)")
            observe(window.screen == screen, "window.screen is the test display")
        }
        observe(!panel.isVisible, "palette hidden after the Settings command")
        let beforeClose = NSApp.windows.filter(\.isVisible).count
        print("COUNT visible-before-close=\(beforeClose)")
        window?.close()
        await IslandVerification.pause(0.6)
        dump("C-after-close")
        observe(NSApp.activationPolicy() == .accessory, "activation policy back to accessory (\(NSApp.activationPolicy().rawValue))")
        let titled = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        observe(titled.isEmpty, "no titled windows left")
        let leftovers = NSApp.windows.filter { $0.isVisible && !($0 is MenuPanel) }.map { String(describing: type(of: $0)) }
        print("LEFTOVER \(leftovers)")
        // The island must still open afterwards.
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.6)
        dump("D-reopen")
        observe(panel.isVisible && screen!.frame.contains(panel.frame), "palette reopens on test display after Settings")
        observe(panel.isKeyWindow, "palette key after reopen")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: 3. IME and dead keys

    private static func clear(_ client: NSTextView) {
        client.insertText("", replacementRange: NSRange(location: 0, length: (client.string as NSString).length))
    }

    private static func ime(core: AppCore, panel: PalettePanel) async {
        IslandLatency.focus(panel)
        guard let client = panel.firstResponder as? NSTextView else {
            observe(false, "first responder is a field editor text view"); return
        }
        print("RESPONDER \(type(of: client)) text='\(client.string)'")
        let none = NSRange(location: NSNotFound, length: 0)
        // Pinyin-style: marked text, then commit.
        client.setMarkedText("ni hao", selectedRange: NSRange(location: 6, length: 0), replacementRange: none)
        await IslandVerification.pause(0.2)
        observe(client.hasMarkedText(), "field editor has marked text")
        observe(core.palette.isComposing, "PaletteState.isComposing true during marked text")
        print("DURING query='\(core.palette.query)' editor='\(client.string)' marked=\(client.markedRange())")
        // Escape during composition: must not close the palette and must not run anything.
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.3)
        observe(panel.isVisible, "Escape during composition keeps palette open")
        print("AFTER-ESC query='\(core.palette.query)' editor='\(client.string)' marked=\(client.hasMarkedText()) composing=\(core.palette.isComposing)")
        // Reset to a clean composition for Enter.
        if client.hasMarkedText() { client.unmarkText() }
        clear(client)
        await IslandVerification.pause(0.1)
        client.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: none)
        await IslandVerification.pause(0.2)
        let modeBefore = core.palette.mode
        let sheet = NSApp.windows.filter(\.isVisible).count
        IslandLatency.key(panel, code: 36, characters: "\r")
        await IslandVerification.pause(0.4)
        observe(panel.isVisible && core.palette.mode == modeBefore, "Return during composition does not close palette or switch mode")
        observe(NSApp.windows.filter(\.isVisible).count == sheet, "Return during composition opened no window (dialog/settings/etc.)")
        print("AFTER-RETURN query='\(core.palette.query)' editor='\(client.string)' marked=\(client.hasMarkedText()) composing=\(core.palette.isComposing) selection=\(core.palette.selection)")
        // Commit.
        client.insertText("你好", replacementRange: none)
        await IslandVerification.pause(0.2)
        observe(!client.hasMarkedText(), "commit clears marked text")
        observe(core.palette.query == "你好", "query equals committed text (query '\(core.palette.query)')")
        await IslandVerification.pause(0.1)
        observe(!core.palette.isComposing, "isComposing false after commit")
        // Cancel: setMarkedText then unmarkText with empty marked text.
        clear(client)
        await IslandVerification.pause(0.1)
        client.setMarkedText("abc", selectedRange: NSRange(location: 3, length: 0), replacementRange: none)
        await IslandVerification.pause(0.15)
        observe(core.palette.isComposing, "composition started for cancel case")
        client.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: none)
        await IslandVerification.pause(0.15)
        observe(!client.hasMarkedText() && !core.palette.isComposing, "empty setMarkedText cancels and clears isComposing")
        print("AFTER-CANCEL query='\(core.palette.query)' editor='\(client.string)' marked=\(client.hasMarkedText()) composing=\(core.palette.isComposing)")
        await IslandVerification.pause(0.6)
        print("AFTER-CANCEL-LATE composing=\(core.palette.isComposing) marked=\(client.hasMarkedText())")
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.4)
        observe(!panel.isVisible, "Escape after a cancelled composition closes the palette (not stuck in composing)")
        if !panel.isVisible {
            core.paletteCoordinator.showPalette(mode: .launcher)
            await IslandVerification.pause(0.6)
            IslandLatency.focus(panel)
        }
        guard let client = panel.firstResponder as? NSTextView else { observe(false, "field editor after reopen"); return }
        // Dead key: acute + e -> e acute.
        clear(client)
        await IslandVerification.pause(0.1)
        client.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        await IslandVerification.pause(0.15)
        observe(core.palette.isComposing, "dead key acute marks composition")
        client.insertText("é", replacementRange: client.markedRange())
        await IslandVerification.pause(0.2)
        observe(core.palette.query == "é" && !core.palette.isComposing && !client.hasMarkedText(),
                "dead key acute + e commits é (query '\(core.palette.query)', composing \(core.palette.isComposing))")
        // Escape during a dead-key composition.
        clear(client)
        await IslandVerification.pause(0.1)
        client.setMarkedText("`", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        await IslandVerification.pause(0.15)
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.3)
        observe(panel.isVisible, "Escape during dead-key composition keeps palette open")
        // Escape with no composition still works as before (control).
        if client.hasMarkedText() { client.unmarkText() }
        clear(client)
        core.palette.query = ""
        await IslandVerification.pause(0.1)
        IslandLatency.key(panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.4)
        observe(!panel.isVisible, "control: Escape without composition closes the palette")
    }
    // MARK: 6. Reduce Motion (in process, never the system setting)

    private static func motion(core: AppCore, panel: PalettePanel) async {
        guard let controller = core.island.active else { observe(false, "active island controller"); return }
        print("SYSTEM accessibilityDisplayShouldReduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) Motion.isEnabled=\(Motion.isEnabled)")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(1.2)
        let rest = controller.outlineBounds
        print("REST outline=\(rest)")
        for enabled in [true, false] {
            core.settings.animationsEnabled = enabled
            Motion.isEnabled = enabled
            for case let p as any AnimatedPanel in NSApp.windows { p.followMotion() }
            await IslandVerification.pause(0.2)
            print("MODE animationsEnabled=\(enabled) Motion.isEnabled=\(Motion.isEnabled) panel.animationBehavior=\(panel.animationBehavior.rawValue)")
            for phase in ["open", "close"] {
                let start = CACurrentMediaTime()
                if phase == "open" { core.paletteCoordinator.showPalette(mode: .launcher) } else { core.paletteCoordinator.hidePalette(restoreFocus: false) }
                var samples: [(Double, CGRect)] = []
                while CACurrentMediaTime() - start < 1.4 {
                    samples.append((CACurrentMediaTime() - start, controller.outlineBounds))
                    try? await Task.sleep(for: .milliseconds(16))
                }
                let final = samples.last!.1
                let settled = samples.first { abs($0.1.width - final.width) < 0.5 && abs($0.1.height - final.height) < 0.5 }?.0 ?? -1
                let distinct = Set(samples.map { "\(Int($0.1.width))x\(Int($0.1.height))" }).count
                print("PHASE \(phase) animations=\(enabled) settledAfter=\(String(format: "%.3f", settled))s distinctSizes=\(distinct) final=\(final) palette=\(panel.frame.size)")
                if phase == "open" {
                    observe(abs(final.width - panel.frame.width) < 1.5 && final.height >= panel.frame.height - 1.5,
                            "open final outline matches palette (animations \(enabled)): \(final) vs \(panel.frame.size)")
                } else {
                    observe(abs(final.width - rest.width) < 0.5 && abs(final.height - rest.height) < 0.5,
                            "close final outline returns to rest (animations \(enabled)): \(final) vs \(rest)")
                }
            }
        }
        core.settings.animationsEnabled = true
    }

    // MARK: 7. Full-screen auxiliary behaviour

    private static func collection(core: AppCore, panel: PalettePanel) {
        core.paletteCoordinator.showPalette(mode: .launcher)
        IslandLatency.key(panel, code: 40, characters: "k", modifiers: .command)
        let wanted: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        for window in NSApp.windows {
            let b = window.collectionBehavior
            print("COLLECTION \(type(of: window)) level=\(window.level.rawValue) behavior=\(b.rawValue)"
                + " canJoinAllSpaces=\(b.contains(.canJoinAllSpaces)) moveToActiveSpace=\(b.contains(.moveToActiveSpace))"
                + " fullScreenAuxiliary=\(b.contains(.fullScreenAuxiliary)) stationary=\(b.contains(.stationary))"
                + " fullScreenNone=\(b.contains(.fullScreenNone)) ignoresCycle=\(b.contains(.ignoresCycle))"
                + " floating=\((window as? NSPanel)?.isFloatingPanel ?? false) hidesOnDeactivate=\((window as? NSPanel)?.hidesOnDeactivate ?? false)"
                + " visible=\(window.isVisible)")
        }
        for name in ["PalettePanel", "IslandBackdrop", "MenuPanel"] {
            if let w = NSApp.windows.first(where: { String(describing: type(of: $0)) == name }) {
                observe(w.collectionBehavior.isSuperset(of: wanted), "\(name) has fullScreenAuxiliary")
            }
        }
    }

    // MARK: 8. VoiceOver labels (in-process accessibility tree, VoiceOver not started)

    private static var axStats = (elements: 0, unlabeled: 0)

    private static func axDescribe(_ element: Any) -> (String, Bool) {
        guard let o = element as? NSAccessibilityProtocol else { return ("<no-ax \(type(of: element))>", false) }
        let role = o.accessibilityRole()?.rawValue ?? "-"
        let label = o.accessibilityLabel() ?? ""
        let title = o.accessibilityTitle() ?? ""
        let help = o.accessibilityHelp() ?? ""
        let value = (o.accessibilityValue() as? String) ?? ""
        let needsName: Set<String> = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuItem", "AXRadioButton", "AXTextField", "AXTextArea", "AXImage", "AXSlider"]
        let named = !(label + title).isEmpty || (!value.isEmpty && role != "AXImage")
        let bad = needsName.contains(role) && !named
        return ("\(role) label='\(label)' title='\(title)' value='\(value.prefix(30))' help='\(help)'", bad)
    }

    private static func axWalk(_ element: Any, depth: Int, tag: String) {
        guard depth < 14, axStats.elements < 600 else { return }
        let (text, bad) = axDescribe(element)
        axStats.elements += 1
        if bad { axStats.unlabeled += 1 }
        print("AX[\(tag)] \(String(repeating: " ", count: depth))\(bad ? "UNLABELED " : "")\(text)")
        guard let o = element as? NSAccessibilityProtocol else { return }
        for child in (o.accessibilityChildren() ?? []) { axWalk(child, depth: depth + 1, tag: tag) }
    }

    private static func axAudit(_ window: NSWindow?, tag: String) {
        guard let window else { observe(false, "\(tag) window present"); return }
        axStats = (0, 0)
        print("AX[\(tag)] window \(type(of: window)) label='\(window.accessibilityLabel() ?? "")' title='\(window.title)'")
        if let content = window.contentView { axWalk(content, depth: 0, tag: tag) }
        print("AXSTATS \(tag) elements=\(axStats.elements) unlabeled=\(axStats.unlabeled)")
        observe(axStats.elements > 1, "\(tag) exposes an accessibility tree (\(axStats.elements) elements)")
        observe(axStats.unlabeled == 0, "\(tag) has no unlabeled controls (\(axStats.unlabeled))")
    }

    private static func accessibility(core: AppCore, panel: PalettePanel) async {
        IslandLatency.focus(panel)
        await IslandVerification.pause(0.5)
        axAudit(panel, tag: "palette")
        if let editor = panel.firstResponder as? NSView { print("FIELD-EDITOR \(axDescribe(editor).0)") }
        IslandLatency.key(panel, code: 40, characters: "k", modifiers: .command)
        await IslandVerification.pause(0.5)
        axAudit(NSApp.windows.first { $0 is MenuPanel && $0.isVisible }, tag: "menu")
        IslandLatency.key(NSApp.keyWindow ?? panel, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.3)
        let box = Box<Bool?>(nil)
        Task { @MainActor in box.value = await core.confirm(title: "AX probe", message: "Synthetic question.",
            symbol: "questionmark.circle", confirmTitle: "Delete", tone: .danger, confirmRole: .destructive) }
        await IslandVerification.pause(0.5)
        axAudit(NSApp.windows.first { $0 is DialogPanel && $0.isVisible }, tag: "dialog")
        if let key = NSApp.keyWindow { IslandLatency.key(key, code: 53, characters: "\u{1b}") }
        await IslandVerification.pause(0.3)
        axAudit(core.island.active?.backdropWindow, tag: "island")
    }
}

@MainActor
final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
#endif
