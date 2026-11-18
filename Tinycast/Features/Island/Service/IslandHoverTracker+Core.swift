import AppKit

extension IslandHoverTracker {
    /// Below the menu bar the zone reaches this far down and past each end of the island (#884 H9).
    static let below = Theme.Spacing.xxl
    static let side = Theme.Spacing.lg

    convenience init(core: AppCore) {
        self.init(world: World(
            input: { Self.input(core) },
            now: { ProcessInfo.processInfo.systemUptime },
            watch: Self.watch,
            unwatch: NSEvent.removeMonitor,
            wake: { deadline, fire in
                let task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(max(deadline - ProcessInfo.processInfo.systemUptime, 0)))
                    guard !Task.isCancelled else { return }
                    fire()
                }
                return { task.cancel() }
            },
            openChanged: { (core.islandPresenter as? IslandPresenter)?.hoverChanged($0) }))
    }

    private static func watch(_ moved: @escaping @MainActor (_ click: Bool) -> Void) -> [Any] {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let clicks: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let elsewhere = NSEvent.addGlobalMonitorForEvents(matching: events) { event in
            moved(clicks.contains(event.type))
        }
        // The global monitor never sees this app's own windows; a row of the island's menu dismisses nothing.
        let here = NSEvent.addLocalMonitorForEvents(matching: events) { event in
            moved(clicks.contains(event.type) && !(event.window is MenuPanel))
            return event
        }
        return [elsewhere, here].compactMap { $0 }
    }

    private static func input(_ core: AppCore) -> IslandHover.Input {
        let island = core.island
        let enabled = core.settings.islandOpensOnHover
        guard let resting = island.resting, let shape = resting.screenShape, let screen = resting.screen else {
            return IslandHover.Input(covered: true, enabled: enabled)
        }
        let inside = IslandHoverZone.contains(NSEvent.mouseLocation, shape: shape,
            menuBarBottom: screen.visibleFrame.maxY, below: below, side: side)
        return IslandHover.Input(inside: inside, buttonHeld: NSEvent.pressedMouseButtons != 0,
            covered: core.palette.isVisible || core.isShowingDialog || NSApp.modalWindow != nil
                || resting.onFullScreenSpace || resting.hasOverlays && !island.overlays.onlyPage,
            menuOpen: island.pillMenu.isOpen, moving: resting.isMoving, enabled: enabled)
    }
}
