import AppKit
import SwiftUI

/// Holds the pages add-ons post and shows them on the resting island while hover opens it (#975).
@MainActor
final class IslandPageHost {
    private(set) var deck = IslandPageDeck()
    private var actions: [String: @MainActor (String) -> Void] = [:]
    private var swipe = IslandPageSwipe()
    private var panel: IslandPagePanel?
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private weak var controller: IslandController?
    private var watchers: [String: @MainActor (Bool) -> Void] = [:]
    private var audience = IslandPageAudience()
    private var hovered = false

    var isOpen: Bool { controller != nil }

    /// The presenter re-opens the hover after this, which draws the change.
    func set(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        deck.set(page, id: id)
        actions[id] = page == nil ? nil : onAction
        announce()
    }

    /// `onChange` hears whether `id`'s data is on show: the island open on Home or on its own page.
    func watch(id: String, onChange: (@MainActor (Bool) -> Void)?) {
        watchers[id] = onChange
        if onChange == nil { audience.forget(id) }
        announce()
    }

    private func announce() {
        let changes = audience.changes(watchers: watchers.keys.sorted(), open: hovered, deck: deck)
        for (id, visible) in changes { watchers[id]?(visible) }
    }

    /// Opens Home, or the one page, on `resting`; false when there is no page to show.
    @discardableResult
    func hover(_ open: Bool, on resting: IslandController?) -> Bool {
        hovered = open && resting != nil
        defer { announce() }
        guard open, let resting, !deck.pages.isEmpty else {
            close()
            return false
        }
        if controller !== resting {
            close()
            deck.open()
            controller = resting
        }
        render()
        return true
    }

    /// Also when the island under it was rebuilt away, which leaves the panel up with no controller.
    func close() {
        controller?.page = nil
        controller = nil
        panel?.orderOut(nil)
        host.rootView = AnyView(EmptyView())
    }

    /// Measures the content, hangs the panel from the island top and grows the outline to it.
    private func render() {
        guard let controller, let screen = controller.screen, let top = controller.openingTop,
              !deck.pages.isEmpty else { return close() }
        let island = AppCore.shared.island
        host.rootView = AnyView(IslandPagesView(deck: deck, select: { [weak self] in self?.select($0) },
                                                act: { [weak self] in self?.act(page: $0, action: $1) })
            .environment(\.metrics, AppCore.shared.settings.interfaceSize.metrics)
            .environment(\.islandFrosted, island.look(for: screen) == .frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark))
        host.layoutSubtreeIfNeeded()
        let panel = panel ?? makePanel()
        let size = IslandPageDeck.outline(content: host.fittingSize, rest: NotchTheme.Size.islandRest,
            notch: controller.notchWidth, radius: Theme.Radius.panel, maxHeight: NotchTheme.Size.islandHost.height - (screen.frame.maxY - top))
        let frame = CGRect(x: controller.openingX(width: size.width) ?? screen.frame.midX - size.width / 2,
                           y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        if controller.page === panel { controller.frameChanged() } else { controller.page = panel }
        if !panel.isVisible {
            panel.sharingType = island.captureSharing
            panel.orderFrontRegardless()
        }
        announce()
    }

    private func select(_ tab: IslandPageDeck.Tab) {
        deck.select(tab)
        render()
    }

    private func act(page id: String, action: String) {
        actions[id]?(action)
    }

    /// A click pins the island, so the keys work until Escape or a click outside (946 rules).
    private func clicked() {
        let hover = AppCore.shared.island.hover
        if !hover.isPinned { hover.togglePin() }
    }

    private func key(_ event: NSEvent) -> Bool {
        guard let key = IslandPageKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                      command: event.modifierFlags.contains(.command)) else { return false }
        switch key {
        case .move(let step): deck.move(by: step)
        case .number(let number): deck.select(number: number)
        case .close: AppCore.shared.island.hover.dismiss()
        case .pin: AppCore.shared.island.hover.togglePin()
        case .refresh:
            let shown = deck.current.map { [$0] } ?? deck.pages
            for page in shown { act(page: page.id, action: IslandPage.refreshAction) }
        }
        if isOpen { render() }
        return true
    }

    private func scrolled(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            swipe = IslandPageSwipe()
            return
        }
        let steps = swipe.steps(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, timestamp: event.timestamp,
            precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
            began: event.phase.contains(.began), ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
            momentum: !event.momentumPhase.isEmpty)
        guard steps != 0 else { return }
        deck.move(by: steps)
        render()
    }

    private func makePanel() -> IslandPagePanel {
        let panel = IslandPagePanel()
        self.panel = panel
        host.wantsLayer = true
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        panel.onClick = { [weak self] in self?.clicked() }
        panel.onMenu = { [weak self] in self?.controller?.openMenu() }
        panel.onKey = { [weak self] in self?.key($0) ?? false }
        panel.onScroll = { [weak self] in self?.scrolled($0) }
        return panel
    }
}

/// The pages' window above the backdrop: clear, takes every click in its frame, key only once clicked.
final class IslandPagePanel: NSPanel {
    var onClick: (@MainActor () -> Void)?
    var onMenu: (@MainActor () -> Void)?
    var onKey: (@MainActor (NSEvent) -> Bool)?
    var onScroll: (@MainActor (NSEvent) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = IslandController.paletteLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Set explicitly, so the clear parts between controls still take the click.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        // The panel covers the island, so its menu click (#917) is forwarded rather than pinning.
        if event.type == .rightMouseDown
            || event.type == .leftMouseDown && event.modifierFlags.contains(.control) {
            onMenu?()
            return
        }
        switch event.type {
        case .leftMouseDown: onClick?()
        case .scrollWheel: onScroll?(event)
        case .keyDown where onKey?(event) == true: return
        default: break
        }
        super.sendEvent(event)
    }
}
