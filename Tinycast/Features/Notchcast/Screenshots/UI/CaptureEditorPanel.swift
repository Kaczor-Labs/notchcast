import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The editor's window, on the stock glass panel recipe; every key goes through the annotation key map.
final class CaptureEditorPanel: NSPanel, AnimatedPanel {
    /// How much of the screen the editor may take before the capture is shown smaller.
    private static let screenFraction: CGFloat = 0.85
    private static let centerLift: CGFloat = 0.04
    private let session: CaptureEditorSession

    /// Opens the editor on the screen under the pointer; the returned closure closes it without answering.
    static func open(_ image: CGImage, finish: @escaping @MainActor (CaptureEditorOutcome) -> Void)
        -> @MainActor () -> Void {
        let screen = NSScreen.underCursor ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let session = CaptureEditorSession(image: image, scale: scale, finish: finish)
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: Theme.Size.settingsWindow)
        let points = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, visible.width * screenFraction / points.width, visible.height * screenFraction / points.height)
        let hosting = NSHostingView(rootView: CaptureEditorView(
            session: session, canvasSize: CGSize(width: points.width * fit, height: points.height * fit)
        ).motionScope())
        hosting.frame.size = hosting.fittingSize
        let panel = CaptureEditorPanel(session: session, content: hosting)
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - hosting.frame.width / 2,
            y: visible.midY - hosting.frame.height / 2 + visible.height * centerLift))
        panel.makeKeyAndOrderFront(nil)
        return { panel.orderOut(nil) }
    }

    private init(session: CaptureEditorSession, content: NSView) {
        self.session = session
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        followMotion()
        isReleasedWhenClosed = false
        isRestorable = false
        title = String(localized: "Capture Editor", table: "NotchcastScreenshots")
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let key = Self.key(event),
            let action = AnnotationKeyAction.action(
                for: key, modifiers: Self.modifiers(event), typingText: session.document.editingTextID != nil)
        else { return super.sendEvent(event) }
        session.perform(action)
    }

    private static func key(_ event: NSEvent) -> AnnotationKeyAction.Key? {
        switch Int(event.keyCode) {
        case kVK_Escape: .escape
        case kVK_Delete, kVK_ForwardDelete: .delete
        case kVK_Return, kVK_ANSI_KeypadEnter: .confirm
        default: event.charactersIgnoringModifiers?.first.map(AnnotationKeyAction.Key.character)
        }
    }

    private static func modifiers(_ event: NSEvent) -> AnnotationKeyAction.Modifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: AnnotationKeyAction.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
