// notchcast-hosted-only
// notchcast-sources: -DDEBUG Tinycast/Windows/Dialog/DialogController.swift Tinycast/Windows/Dialog/DialogPanel.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogView.swift Tinycast/Windows/Dialog/DialogRequest.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogTextField.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/DialogSecretField.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
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
import Vision

/// `askSecret` from a registered add-on's context through the real dialog, leaving no trace behind.
@MainActor
@main
struct NotchcastAskSecretTest {
    static var failures = 0
    static let noSelection = NSRange(location: NSNotFound, length: 0)

    static func check(_ label: String, _ ok: Bool) {
        // Stderr is unbuffered: stdout to a log file is lost when `finish` traps.
        if !ok { failures += 1; FileHandle.standardError.write(Data("FAIL \(label)\n".utf8)) }
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate()
        let controller = DialogController(settings: AppSettings(), onPresentationChanged: { _ in })
        let suite = "nc-Notchcast-ask-secret-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let addons = NotchcastController(
            addons: [ArchivesProbe.self, DownloadsProbe.self, BlankProbe.self], defaults: UserDefaults(suiteName: suite)!,
            hub: NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
                fatalError("the probe declares no tap")
            }),
            dictation: FakeDictation(), presenter: SilentPresenter())
        addons.wireAskSecret { [controller] requester, title, message, fieldTitle, confirmTitle in
            await controller.askSecret(
                requester: requester, title: title, message: message, fieldTitle: fieldTitle,
                confirmTitle: confirmTitle)
        }
        context = addons.slots[0].context
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
        check(
            "the requester line names the add-on from its registration, got \(state.requesterLine)",
            state.requesterLine == "Asked by Archives in Notchcast")
        if let drawn = drawnText(in: panel) {
            check(
                "Vision reads the requester line in the drawn dialog, read \(drawn)",
                drawn.contains { $0.contains("Asked by Archives in Notchcast") })
        }
        check("the title is the add-on's, the requester line is not", controller.shown?.title == "Archive Password")
        let editor = panel.firstResponder as? NSTextView
        check("the hidden field has focus on open", editor?.delegate is NSSecureTextField)
        check("Secure Input is on while the field has focus", IsSecureEventInputEnabled())
        editor?.insertText("hunter2", replacementRange: noSelection)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        spin { state.text == "hunter2!pw" }
        check("typing and ⌘V's paste reach the field, got \(state.text.count) characters", state.text == "hunter2!pw")
        panel.makeFirstResponder(nil)
        check("the field let go of focus while the dialog stays key", panel.isKeyWindow && panel.firstResponder === panel)
        check("Secure Input holds while the key dialog's field has no focus", IsSecureEventInputEnabled())

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
        check("Return answers the typed text, got \(shape(answer))", answer == .some("hunter2!pw"))
        closed(controller, state, "Return")

        // Esc cancels.
        answer = nil
        Task { answer = await ask(controller) }
        guard let escPanel = spinForPanel() else { return finish() }
        guard case .secret(let escState)? = controller.shown?.accessory else { return finish() }
        (escPanel.firstResponder as? NSTextView)?.insertText("x", replacementRange: noSelection)
        escPanel.sendEvent(key(kVK_Escape, "\u{1b}"))
        spin { answer != nil }
        check("Esc answers nil, got \(shape(answer))", answer == .some(nil))
        closed(controller, escState, "Esc")

        // The Cancel button and a stock dialog still dismissed by click-away.
        answer = nil
        Task { answer = await ask(controller) }
        guard let cancelPanel = spinForPanel() else { return finish() }
        guard case .secret(let cancelState)? = controller.shown?.accessory else { return finish() }
        (cancelPanel.firstResponder as? NSTextView)?.insertText("typed", replacementRange: noSelection)
        spin { cancelState.text == "typed" }
        check("Cancel: the text was typed before cancelling", cancelState.text == "typed")
        cancelPanel.onKey?(.cancel)
        spin { answer != nil }
        check("Cancel answers nil, got \(shape(answer))", answer == .some(nil))
        closed(controller, cancelState, "Cancel")
        check("Cancel: the pasteboard is untouched", pasteboard.changeCount == pasteboardCount)

        // The asking job is cancelled while the dialog is open with text typed.
        answer = nil
        let job = Task { answer = await ask(controller) }
        guard let jobPanel = spinForPanel() else { return finish() }
        guard case .secret(let jobState)? = controller.shown?.accessory else { return finish() }
        (jobPanel.firstResponder as? NSTextView)?.insertText("orphan", replacementRange: noSelection)
        spin { jobState.text == "orphan" }
        check("job cancelled: the text was typed first", jobState.text == "orphan")
        job.cancel()
        spin { answer != nil }
        check("job cancelled: the answer is nil, never the typed text, got \(shape(answer))", answer == .some(nil))
        closed(controller, jobState, "job cancelled")

        var confirmed: Bool?
        Task {
            confirmed = await controller.confirm(
                title: "Delete?", message: nil, symbol: nil, tone: .neutral, confirmTitle: "Delete",
                confirmRole: .destructive)
        }
        guard let stockPanel = spinForPanel() else { return finish() }
        check("a stock dialog holds no Secure Input while key", stockPanel.isKeyWindow && !IsSecureEventInputEnabled())
        other.makeKeyAndOrderFront(nil)
        spin { confirmed != nil }
        check("a stock dialog still cancels on click-away", confirmed == false)
        other.orderOut(nil)

        proveRequesterIsDrawn(controller, addons.slots.map(\.context))

        check(
            "the pasteboard, and so clipboard history, never saw the secret",
            pasteboard.changeCount == pasteboardCount && pasteboard.string(forType: .string) == "!pw")
        finish()
    }

    static var context: NotchcastContext?

    static func ask(_ controller: DialogController) async -> String? {
        await context?.askSecret?("Archive Password", "Enter the password for backup.zip.", "Password", "Extract")
    }

    /// Vision on the CPU; nil, with a note, where it cannot run, as the pixel proof carries the line.
    static func drawnText(in panel: NSWindow) -> [String]? {
        guard let view = panel.contentView, let image = snapshot(view)?.image else { return [] }
        var lines: [String]??
        Task {
            var request = RecognizeTextRequest()
            request.usesLanguageCorrection = false
            for (stage, devices) in request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
            do {
                lines = try await request.perform(on: image).compactMap { $0.topCandidates(1).first?.string }
            } catch {
                FileHandle.standardError.write(Data("NOTE Vision cannot run here: \(error)\n".utf8))
                lines = .some(nil)
            }
        }
        // A fresh runner compiles Vision's model on first use, which can take most of a minute.
        spin(turns: 12_000) { lines != nil }
        guard let lines else {
            FileHandle.standardError.write(Data("NOTE Vision gave no answer in two minutes\n".utf8))
            return nil
        }
        return lines
    }

    /// The real dialog drawn for three registered add-ons differs only in the line under the field.
    static func proveRequesterIsDrawn(_ controller: DialogController, _ contexts: [NotchcastContext]) {
        let renders = contexts.compactMap { requesterRender(controller, $0) }
        guard renders.count == 3 else { return check("the dialog rendered for all three add-ons", false) }
        let (archives, below) = renders[0]
        for (name, other) in [("Downloads", renders[1].shot), ("an empty name", renders[2].shot)] {
            let rows = differingRows(archives, other)
            check("Archives and \(name) draw different pixels", rows != nil)
            guard let rows else { continue }
            check(
                "Archives and \(name) differ only in one caption line under the field, rows \(rows) "
                    + "with the field ending at \(below)",
                rows.lowerBound >= below && rows.lowerBound <= below + 64 && rows.count <= 48)
        }
    }

    /// The dialog at 2x on black with no focus ring or caret, and the pixel row the secret field ends on.
    static func requesterRender(_ controller: DialogController, _ asking: NotchcastContext) -> (shot: Snapshot, below: Int)? {
        var answer: String??
        Task {
            answer = await asking.askSecret?("Archive Password", "Enter the password for backup.zip.", "Password", "Extract")
        }
        guard let panel = spinForPanel(), let view = panel.contentView,
            case .secret(let state)? = controller.shown?.accessory
        else { return nil }
        panel.makeFirstResponder(nil)
        var shot = snapshot(view)
        for _ in 0..<50 {
            spin(turns: 5) { false }
            let next = snapshot(view)
            if next?.bytes == shot?.bytes { break }
            shot = next
        }
        let field = secureField(in: view)
        check("the secret field is an AppKit field to measure from", field != nil)
        panel.onKey?(.cancel)
        spin { answer != nil }
        closed(controller, state, "requester render")
        guard let shot, let field else { return nil }
        let frame = view.convert(field.bounds, from: field)
        return (shot, Int((view.isFlipped ? frame.maxY : view.bounds.height - frame.minY) * 2))
    }

    static func secureField(in view: NSView) -> NSSecureTextField? {
        if let field = view as? NSSecureTextField { return field }
        return view.subviews.lazy.compactMap { secureField(in: $0) }.first
    }

    struct Snapshot {
        let image: CGImage
        let bytes: [UInt8]
        let bytesPerRow: Int
    }

    static func snapshot(_ view: NSView) -> Snapshot? {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let drawn = rep.cgImage,
            let flat = CGContext(
                data: nil, width: drawn.width, height: drawn.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height)
        flat.setFillColor(.black)
        flat.fill(bounds)
        flat.draw(drawn, in: bounds)
        guard let image = flat.makeImage(), let data = flat.data else { return nil }
        let bytes = [UInt8](UnsafeRawBufferPointer(start: data, count: flat.bytesPerRow * flat.height))
        return Snapshot(image: image, bytes: bytes, bytesPerRow: flat.bytesPerRow)
    }

    /// Top-down pixel rows where the two differ; all rows when their sizes differ, nil when identical.
    static func differingRows(_ a: Snapshot, _ b: Snapshot) -> ClosedRange<Int>? {
        let height = a.bytes.count / a.bytesPerRow
        guard a.bytesPerRow == b.bytesPerRow, a.bytes.count == b.bytes.count else {
            return 0...max(height, b.bytes.count / max(b.bytesPerRow, 1))
        }
        let rows = (0..<height).filter { row in
            let range = row * a.bytesPerRow..<(row + 1) * a.bytesPerRow
            return a.bytes[range] != b.bytes[range]
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        return first...last
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

    /// Nil when no answer came, else whether it is nil or how long it is, never the text itself.
    static func shape(_ answer: String??) -> String {
        switch answer {
        case nil: "no answer"
        case .some(nil): "nil"
        case .some(let text?): "\(text.count) characters"
        }
    }

    /// Turns the main run loop until `done`, capped so a broken path fails instead of hanging.
    static func spin(turns: Int = 300, _ done: () -> Bool) {
        for _ in 0..<turns where !done() {
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

enum ArchivesProbe: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "archives", title: "Archives", subtitle: "", category: .filesDownloads)]
}

enum DownloadsProbe: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "downloads", title: "Downloads", subtitle: "", category: .filesDownloads)]
}

enum BlankProbe: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "blank", title: "", subtitle: "", category: .filesDownloads)]
}

final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
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
