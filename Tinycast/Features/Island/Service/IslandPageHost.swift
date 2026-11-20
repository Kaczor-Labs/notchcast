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
    private var focus = IslandPageFocus()
    /// The tab `showPage` asked for, chosen when the pin it waits on opens the island.
    private var wanted: IslandPageDeck.Tab?

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

    /// The pill's shown notice or status heads the open page; `onTap` makes that row a button.
    func show(_ notice: IslandNotice?, onTap: (@MainActor () -> Void)?) {
        actions[IslandPageDeck.noticeID] = if let onTap { { _ in onTap() } } else { nil }
        let before = deck
        deck.show(notice, tappable: onTap != nil)
        if deck != before, isOpen { render() }
    }

    private func announce() {
        let changes = audience.changes(watchers: watchers.keys.sorted(), open: hovered, deck: deck)
        for (id, visible) in changes { watchers[id]?(visible) }
    }

    /// Opens Home, or the one page, on `resting`; false when a notice or `glance` keeps its own form.
    @discardableResult
    func hover(_ open: Bool, on resting: IslandController?, glance: Bool = false) -> Bool {
        hovered = open && resting != nil
        defer { announce() }
        guard open, let resting, deck.opens(glance: glance) else {
            if !open { focus = IslandPageFocus() }
            close()
            return false
        }
        if controller !== resting {
            close()
            deck.open()
            controller = resting
        }
        if let wanted {
            // A pin whose wait ran out never opened, so a plain hover later still opens Home.
            if AppCore.shared.island.hover.isPinned { deck.select(wanted) }
            self.wanted = nil
        }
        render()
        keyOnPin()
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
        guard let controller, let screen = controller.screen, let top = controller.openingTop else { return close() }
        let island = AppCore.shared.island
        host.rootView = AnyView(IslandPagesView(deck: deck, select: { [weak self] in self?.select($0) },
                                                act: { [weak self] in self?.act(page: $0, action: $1) })
            .environment(\.metrics, AppCore.shared.settings.interfaceSize.metrics)
            .environment(\.islandFrosted, island.look(for: screen) == .frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark))
        host.layoutSubtreeIfNeeded()
        let panel = panel ?? makePanel()
        let size = IslandPageDeck.outline(
            content: host.fittingSize, rest: NotchTheme.Size.islandRest, notch: controller.notchWidth,
            radius: Theme.Radius.panel, maxHeight: NotchTheme.Size.islandHost.height - (screen.frame.maxY - top))
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

    func showPage(id: String) {
        guard deck.page(id) != nil else { return }
        let tracker = AppCore.shared.island.hover
        if isOpen, deck.selection == .page(id) { return tracker.dismiss() }
        wanted = .page(id)
        guard let controller else { return tracker.pinWhenUncovered() }
        tracker.pin()
        hover(true, on: controller)
    }

    private func select(_ tab: IslandPageDeck.Tab) {
        deck.select(tab)
        render()
    }

    func act(page id: String, action: String) {
        actions[id]?(action)
    }

    /// A click on the bare island lands on the island's window, so the page keys need the panel key.
    private func keyOnPin() {
        if focus.takesKey(pinned: AppCore.shared.island.hover.isPinned) { panel?.makeKey() }
    }

    /// A click pins the island, so the keys work until Escape or a click outside (946 rules).
    private func clicked() {
        AppCore.shared.island.hover.pin()
        keyOnPin()
    }

    private func key(_ event: NSEvent) -> Bool {
        guard let key = IslandPageKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                      command: event.modifierFlags.contains(.command)) else { return false }
        if let target = deck.pageAction(for: key) {
            act(page: target.page, action: target.action)
            keyOnPin()
            return true
        }
        switch key {
        case .move(let step): deck.move(by: step)
        case .number(let number): deck.select(number: number)
        case .close: AppCore.shared.island.hover.dismiss()
        case .pin: AppCore.shared.island.hover.togglePin()
        case .refresh:
            let shown = deck.current.map { [$0] } ?? deck.pages
            for page in shown { act(page: page.id, action: IslandPage.refreshAction) }
        case .space, .step: return false
        }
        if isOpen { render() }
        keyOnPin()
        return true
    }

    private func scrolled(_ event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) else {
            swipe = IslandPageSwipe()
            return
        }
        let steps = swipe.steps(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, timestamp: event.timestamp,
            precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
            began: event.phase.contains(.began), ended: !event.phase.isDisjoint(with: [.ended, .cancelled]),
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
        panel.onMenu = { [weak self] in self?.controller?.canvas.onMenu?() }
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
