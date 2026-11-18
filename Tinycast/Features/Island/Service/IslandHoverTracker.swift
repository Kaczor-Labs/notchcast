import AppKit

/// Watches the pointer over the resting island and runs `IslandHover`'s clocks (#884).
@MainActor
final class IslandHoverTracker {
    private unowned let core: AppCore
    private var hover = IslandHover()
    private var monitors: [Any] = []
    private var clock: Task<Void, Never>?
    /// Below the menu bar the zone reaches this far down and past each end of the island (#884 H9).
    static let below = Theme.Spacing.xxl
    static let side = Theme.Spacing.lg

    init(core: AppCore) { self.core = core }

    var isOpen: Bool { hover.isOpen }

    func start() {
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let clicks: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let elsewhere = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerMoved(click: clicks.contains(event.type))
        }
        // The global monitor never sees this app's own windows, the island's included.
        let here = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerMoved(click: false)
            return event
        }
        monitors = [elsewhere, here].compactMap { $0 }
    }

    /// Something other than the pointer changed: the launcher, a question, the menu, the setting.
    func refresh() { apply(hover.update(input, at: now)) }

    /// Command-P on an island page that holds the keyboard; hover itself never takes it (#884 H15).
    func togglePin() {
        let was = hover.isOpen
        hover.togglePin(at: now)
        apply(was != hover.isOpen)
    }

    private func pointerMoved(click: Bool) {
        let next = input
        if click, hover.isPinned, !next.inside { hover.dismiss() }
        apply(hover.update(next, at: now))
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var input: IslandHover.Input {
        let island = core.island
        guard let resting = island.resting, let shape = resting.screenShape, let screen = resting.screen else {
            return IslandHover.Input(covered: true)
        }
        let inside = IslandHoverZone.contains(NSEvent.mouseLocation, shape: shape,
            menuBarBottom: screen.visibleFrame.maxY, below: Self.below, side: Self.side)
        return IslandHover.Input(inside: inside, buttonHeld: NSEvent.pressedMouseButtons != 0,
            covered: core.palette.isVisible || core.isShowingDialog || NSApp.modalWindow != nil
                || resting.onFullScreenSpace || resting.hasOverlays,
            menuOpen: island.pillMenu.isOpen, moving: resting.isMoving, enabled: core.settings.islandOpensOnHover)
    }

    private func apply(_ changed: Bool) {
        if changed { (core.islandPresenter as? IslandPresenter)?.hoverChanged(hover.isOpen) }
        clock?.cancel()
        clock = hover.deadline.map { deadline in
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(deadline - ProcessInfo.processInfo.systemUptime, 0)))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    isolated deinit {
        clock?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
    }
}
