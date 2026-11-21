// notchcast-hosted-only
// notchcast-sources: -DDEBUG Tinycast/Windows/Dialog/DialogController.swift Tinycast/Windows/Dialog/DialogPanel.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogView.swift Tinycast/Windows/Dialog/DialogRequest.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogTextField.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/DialogSecretField.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/SecureInputHold.swift
// notchcast-sources: Tinycast/DesignSystem/RevealableSecureField.swift Tinycast/DesignSystem/Interaction/Motion.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/AnimatedPanel.swift Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Platform/WindowLevel.swift Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift Tinycast/DesignSystem/KeyCapChip.swift
// notchcast-sources: Tinycast/DesignSystem/ModalActionButtonStyle.swift Tinycast/DesignSystem/SymbolImage.swift
// notchcast-sources: Tinycast/DesignSystem/Tooltip.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/VolumeLevel.swift
// notchcast-sources: Tinycast/Features/Settings/InterfaceSize.swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// `askSecret` through the real controller and panel: the answer and Cancel paths, focus, paste,
/// click-away, Secure Input on while key and off after every close, and no trace left behind.
@MainActor
@main
struct NotchcastAskSecretTest {
    static var failures = 0
    static let noSelection = NSRange(location: NSNotFound, length: 0)

    static func check(_ label: String, _ ok: Bool) {
        if !ok { failures += 1; print("FAIL \(label)") }
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate()
        let controller = DialogController(settings: AppSettings(), onPresentationChanged: { _ in })
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("!pw", forType: .string)
        let pasteboardCount = pasteboard.changeCount
        check("Secure Input starts off", !IsSecureEventInputEnabled())

        // Return confirms, with text typed and pasted, after a click-away that keeps the question.
        var answer: String??
        Task { answer = await ask(controller) }
        guard let panel = spinForPanel() else { return finish() }
        check("the dialog is key", panel.isKeyWindow)
        guard case .secret(let state)? = controller.shown?.accessory else {
            check("the open dialog carries the secret accessory", false)
            return finish()
        }
        check("Notchcast's line names the asking add-on", state.requester == "Archives")
        check("the title is the add-on's, the requester line is not", controller.shown?.title == "Archive Password")
        let editor = panel.firstResponder as? NSTextView
        check("the hidden field has focus on open", editor?.delegate is NSSecureTextField)
        check("Secure Input is on while the field has focus", IsSecureEventInputEnabled())
        editor?.insertText("hunter2", replacementRange: noSelection)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        spin { state.text == "hunter2!pw" }
        check("typing and ⌘V's paste reach the field, got \(state.text.count) characters", state.text == "hunter2!pw")

        let other = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered, defer: false)
        other.makeKeyAndOrderFront(nil)
        spin { !panel.isKeyWindow }
        check("another window took key status", !panel.isKeyWindow)
        check("click-away keeps the secret question open", controller.shown != nil && answer == nil)
        check("Secure Input is off while another window is key", !IsSecureEventInputEnabled())
        other.orderOut(nil)
        panel.makeKeyAndOrderFront(nil)
        spin { panel.isKeyWindow }
        check("Secure Input is back on when the dialog is key again", IsSecureEventInputEnabled())

        panel.sendEvent(key(kVK_Return, "\r"))
        spin { answer != nil }
        check("Return answers the typed text", answer == .some("hunter2!pw"))
        closed(controller, state, "Return")

        // Esc cancels.
        answer = nil
        Task { answer = await ask(controller) }
        guard let escPanel = spinForPanel() else { return finish() }
        guard case .secret(let escState)? = controller.shown?.accessory else { return finish() }
        (escPanel.firstResponder as? NSTextView)?.insertText("x", replacementRange: noSelection)
        escPanel.sendEvent(key(kVK_Escape, "\u{1b}"))
        spin { answer != nil }
        check("Esc answers nil", answer == .some(nil))
        closed(controller, escState, "Esc")

        // The Cancel button and a stock dialog still dismissed by click-away.
        answer = nil
        Task { answer = await ask(controller) }
        guard let cancelPanel = spinForPanel() else { return finish() }
        guard case .secret(let cancelState)? = controller.shown?.accessory else { return finish() }
        cancelPanel.onKey?(.cancel)
        spin { answer != nil }
        check("Cancel answers nil", answer == .some(nil))
        closed(controller, cancelState, "Cancel")

        var confirmed: Bool?
        Task {
            confirmed = await controller.confirm(
                title: "Delete?", message: nil, symbol: nil, tone: .neutral, confirmTitle: "Delete",
                confirmRole: .destructive)
        }
        guard spinForPanel() != nil else { return finish() }
        other.makeKeyAndOrderFront(nil)
        spin { confirmed != nil }
        check("a stock dialog still cancels on click-away", confirmed == false)
        check("a stock dialog never holds Secure Input", !IsSecureEventInputEnabled())
        other.orderOut(nil)

        check(
            "the pasteboard, and so clipboard history, never saw the secret",
            pasteboard.changeCount == pasteboardCount && pasteboard.string(forType: .string) == "!pw")
        finish()
    }

    static func ask(_ controller: DialogController) async -> String? {
        await controller.askSecret(
            requester: "Archives", title: "Archive Password", message: "Enter the password for backup.zip.",
            fieldTitle: "Password", confirmTitle: "Extract")
    }

    static func closed(_ controller: DialogController, _ state: SecretFieldState, _ how: String) {
        spin { !NSApp.windows.contains { $0 is DialogPanel && $0.isVisible } }
        check("\(how): Debug's shown request is dropped", controller.shown == nil)
        check("\(how): the field state is cleared after return", state.text.isEmpty)
        check("\(how): Secure Input is off", !IsSecureEventInputEnabled())
        check("\(how): the dialog is gone", !NSApp.windows.contains { $0 is DialogPanel && $0.isVisible })
    }

    static func finish() {
        guard failures == 0 else { fatalError("\(failures) ask-secret checks failed") }
        print("PASS askSecret answers, cancels, survives click-away and leaves Secure Input off")
    }

    static func spinForPanel() -> DialogPanel? {
        spin { NSApp.keyWindow is DialogPanel }
        let panel = NSApp.windows.lazy.compactMap { $0 as? DialogPanel }.first { $0.isVisible }
        check("the dialog opened", panel != nil)
        return panel
    }

    /// Turns the main run loop until `done`, capped so a broken path fails instead of hanging.
    static func spin(_ done: () -> Bool) {
        for _ in 0..<300 where !done() {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    static func key(_ code: Int, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: UInt16(code))!
    }
}

/// The controller reads only the interface size; the island places the panel itself.
@MainActor
final class AppSettings {
    var interfaceSize = InterfaceSize.standard
}

@MainActor
final class AppCore {
    static let shared = AppCore()
    let island = Island()

    @MainActor
    final class Island {
        let overlays = Overlays()
        func frosted(on screen: NSScreen?) -> Bool { false }
    }

    @MainActor
    final class Overlays {
        func placeQuestion(_ panel: NSPanel) { panel.center() }
        func dismissed(_ panel: NSPanel) {}
    }
}

/// The other accessories are not under test; stand-ins keep the controller and view whole.
final class VolumeState {
    var level: Double
    init(level: Double) { self.level = level }
}

final class SnippetArgumentsState {
    struct Argument { let options: [String] }
    let arguments: [Argument] = []
    let values: [String: String] = [:]
    var asksOnlyForChoices: Bool { false }
    init(arguments: [SnippetTemplateEngine.MissingArgument]) {}
    func moveFocus(backwards: Bool) {}
    func focusFirstArgument() {}
}

enum SnippetTemplateEngine {
    struct MissingArgument {}
}

final class ClipboardEditState {
    var text: String
    init(text: String) { self.text = text }
}

struct VolumeSlider: View {
    let state: VolumeState
    var body: some View { EmptyView() }
}

struct SnippetArgumentFields: View {
    let state: SnippetArgumentsState
    var onSubmit: () -> Void = {}
    var body: some View { EmptyView() }
}

struct ClipboardEditField: View {
    let state: ClipboardEditState
    var body: some View { EmptyView() }
}
