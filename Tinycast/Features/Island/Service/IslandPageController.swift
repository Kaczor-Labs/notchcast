import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows one registered page under the pill, where the island grows around it as it does a question.
@MainActor
final class IslandPageController {
    private var pages: [String: IslandPage] = [:]
    private var panel: IslandPagePanel?
    private(set) var shown: String?

    var isOpen: Bool { shown != nil }
    var owners: Set<String> { Set(pages.keys) }

    func register(_ page: IslandPage) {
        pages[page.owner] = page
        if shown == page.owner { show(page) }
    }

    func unregister(owner: String) {
        pages[owner] = nil
        if shown == owner { close() }
    }

    /// `keyboard` is a click or a command: hover never takes the keyboard (D27).
    func open(owner: String, keyboard: Bool) {
        guard let page = pages[owner] else { return }
        if shown != owner { show(page) }
        if keyboard { panel?.makeKeyAndOrderFront(nil) }
    }

    func close() {
        guard shown != nil, let panel else { return }
        shown = nil
        if panel.isKeyWindow { panel.resignKey() }
        panel.fadeOut(duration: Theme.Duration.exit) { [weak panel] in panel?.orderOut(nil) }
        AppCore.shared.island.overlays.dismissed(panel)
    }

    private func show(_ page: IslandPage) {
        let island = AppCore.shared.island
        let panel = panel ?? makePanel()
        shown = page.owner
        panel.onKey = page.onKey
        let root = page.view().environment(\.islandFrosted, island.frosted(on: island.resting?.screen))
        panel.contentView = NSHostingView(rootView: root.frame(width: page.size.width, height: page.size.height))
        panel.setContentSize(page.size)
        island.overlays.placePage(panel)
        if panel.isVisible { panel.cancelFade() } else {
            panel.fadeIn(duration: Theme.Duration.dialogEnter) { panel.orderFrontRegardless() }
        }
    }

    private func makePanel() -> IslandPagePanel {
        let panel = IslandPagePanel()
        panel.onEscape = { AppCore.shared.island.hover.dismiss() }
        panel.onPin = { AppCore.shared.island.hover.togglePin() }
        panel.onKeyed = { AppCore.shared.island.hover.pin() }
        self.panel = panel
        return panel
    }
}

final class IslandPagePanel: NSPanel {
    var onKey: @MainActor (IslandPageKey) -> Bool = { _ in false }
    var onEscape: (@MainActor () -> Void)?
    var onPin: (@MainActor () -> Void)?
    /// A click hands the page the keyboard and holds it open until Escape or a click outside (D27).
    var onKeyed: (@MainActor () -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onKeyed?()
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { return super.sendEvent(event) }
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape: onEscape?()
        case kVK_ANSI_P where command: onPin?()
        case let code:
            let key: IslandPageKey? = switch code {
            case kVK_Space where !command: .space
            case kVK_LeftArrow: .left
            case kVK_RightArrow: .right
            case kVK_UpArrow: .up
            case kVK_DownArrow: .down
            case kVK_ANSI_R where command: .refresh
            default: nil
            }
            if key.map(onKey) != true { super.sendEvent(event) }
        }
    }
}
