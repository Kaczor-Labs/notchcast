import AppKit

/// Takes the keyboard without activating Notchcast while a caller holds it, and gives it back.
@MainActor
final class IslandKeyHold {
    private var panel: IslandKeyPanel?

    /// `near` is the resting pill's frame, so the one-point window sits under the island.
    func hold(_ onKey: (@MainActor (IslandHeldKey) -> Void)?, near frame: CGRect?) {
        guard let onKey else {
            panel?.onKey = nil
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? IslandKeyPanel()
        self.panel = panel
        panel.onKey = onKey
        if let frame { panel.setFrameOrigin(CGPoint(x: frame.midX, y: frame.midY)) }
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Clear, one point square and mouse-transparent, so only its key focus is felt.
private final class IslandKeyPanel: NSPanel {
    var onKey: (@MainActor (IslandHeldKey) -> Void)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat, let onKey, let key = IslandHeldKey(keyCode: Int(event.keyCode)) {
            return onKey(key)
        }
        super.sendEvent(event)
    }
}
