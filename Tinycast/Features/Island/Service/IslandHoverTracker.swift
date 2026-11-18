import Foundation

/// Watches the pointer over the resting island and runs `IslandHover`'s clocks (#884).
@MainActor
final class IslandHoverTracker {
    /// What the tracker reads from and does to the app; `IslandHoverTracker+Core.swift` binds the real one.
    struct World {
        var input: @MainActor () -> IslandHover.Input
        var now: @MainActor () -> TimeInterval
        /// Installs the pointer monitors; each event says whether it was a click that may dismiss a pin.
        var watch: @MainActor (_ moved: @escaping @MainActor (_ click: Bool) -> Void) -> [Any]
        var unwatch: @MainActor (Any) -> Void
        /// Calls `fire` once `deadline` passes; the returned closure cancels it.
        var wake: @MainActor (_ deadline: TimeInterval, _ fire: @escaping @MainActor () -> Void)
            -> @MainActor () -> Void
        var openChanged: @MainActor (_ isOpen: Bool) -> Void
    }

    private let world: World
    private var hover = IslandHover()
    private var monitors: [Any] = []
    private var cancelWake: (@MainActor () -> Void)?

    init(world: World) { self.world = world }

    var isOpen: Bool { hover.isOpen }
    var isWatching: Bool { !monitors.isEmpty }

    func start() { refresh() }

    /// Something other than the pointer changed: the launcher, a question, the menu, the setting.
    func refresh() { pointerMoved(click: false) }

    /// Command-P on an island page that holds the keyboard; hover itself never takes it (#884 H15).
    func togglePin() {
        let was = hover.isOpen
        hover.togglePin(at: world.now())
        apply(was != hover.isOpen)
    }

    /// A click on an add-on's page holds the island open as a pin does, until Escape or a click outside.
    func pin() {
        guard !hover.isPinned else { return }
        togglePin()
    }

    /// Escape on a page: closes whether the pointer is there or not.
    func dismiss() {
        let was = hover.isOpen
        hover.dismiss()
        apply(was != hover.isOpen)
    }

    private func pointerMoved(click: Bool) {
        let next = world.input()
        let was = hover.isOpen
        if click, hover.isPinned, !next.inside { hover.dismiss() }
        hover.update(next, at: world.now())
        apply(was != hover.isOpen)
    }

    private func apply(_ changed: Bool) {
        if changed { world.openChanged(hover.isOpen) }
        // Off, the pointer is only watched while a pin waits for its outside click.
        watch(hover.input.enabled || hover.isPinned)
        cancelWake?()
        cancelWake = hover.deadline.map { world.wake($0) { [weak self] in self?.refresh() } }
    }

    private func watch(_ wanted: Bool) {
        if wanted, monitors.isEmpty {
            monitors = world.watch { [weak self] in self?.pointerMoved(click: $0) }
        } else if !wanted, !monitors.isEmpty {
            monitors.forEach(world.unwatch)
            monitors = []
        }
    }

    isolated deinit {
        cancelWake?()
        monitors.forEach(world.unwatch)
    }
}
