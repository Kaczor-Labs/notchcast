import AppKit

/// Takes the keyboard without activating Notchcast while a caller holds it, and gives it back.
@MainActor
final class IslandKeyHold {
    private var panel: IslandKeyPanel?
    private(set) var lease = IslandKeyLease()

    /// `near` is the resting pill's screen shape, so the one-point window sits on the island.
    func hold(_ onKey: (@MainActor (IslandHeldKey) -> Void)?, near shape: CGRect?, during notice: String?) {
        guard let onKey else { return release() }
        lease.take(during: notice)
        let panel = panel ?? IslandKeyPanel()
        self.panel = panel
        panel.onKey = onKey
        panel.onResign = { [weak self] in self?.release() }
        if let shape { panel.setFrameOrigin(CGPoint(x: shape.midX, y: shape.midY)) }
        panel.makeKeyAndOrderFront(nil)
    }

    func noticesChanged(live: (String) -> Bool) {
        if lease.outlived(live: live) { release() }
    }

    func release() {
        lease.give()
        panel?.onResign = nil
        panel?.onKey = nil
        panel?.orderOut(nil)
    }

    isolated deinit { release() }
}

/// Clear, one point square and mouse-transparent, so only its key focus is felt.
private final class IslandKeyPanel: NSPanel {
    var onKey: (@MainActor (IslandHeldKey) -> Void)?
    var onResign: (@MainActor () -> Void)?

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

    /// Once focus leaves, the hold never comes back by itself, so it can never swallow keys later.
    override func resignKey() {
        super.resignKey()
        onKey = nil
        guard let resigned = onResign else { return }
        onResign = nil
        orderOut(nil)
        resigned()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat, let onKey, let key = IslandHeldKey(keyCode: Int(event.keyCode)) {
            return onKey(key)
        }
        super.sendEvent(event)
    }
}
