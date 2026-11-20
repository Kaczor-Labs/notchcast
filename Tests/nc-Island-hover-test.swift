// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandHoverTracker.swift
// notchcast-reads: Tinycast/Features/Island/Service/IslandCoordinator.swift
// notchcast-reads: Tinycast/Features/Island/Service/IslandController.swift
// notchcast-reads: Tinycast/Features/Island/Service/IslandPillMenu.swift
// notchcast-reads: Tinycast/Features/Island/Service/IslandHoverTracker+Core.swift
import CoreGraphics
import Foundation

@main
@MainActor
struct IslandHoverTest {
    typealias Input = IslandHover.Input
    static let open = IslandHover.openDelay
    static let close = IslandHover.closeDelay

    static func main() throws {
        delays()
        passThrough()
        leaving()
        buttons()
        covered()
        settingOff()
        pin()
        zone()
        content()
        menuEscape()
        monitors()
        pinnedClick()
        topRowRest()
        primaryClick()
        try clickHooks()
        try refreshHooks()
        pinWhenUncovered()
        print("IslandHoverTest passed")
    }

    static func delays() {
        precondition(open > 0 && open <= 0.2 && close > 0 && close <= 0.4, "the delays stay short (#884 H8)")
        var hover = IslandHover()
        hover.update(Input(inside: true), at: 10)
        precondition(!hover.isOpen && hover.deadline == 10 + open, "entering starts the open clock, it opens nothing")
        precondition(!hover.tick(at: 10 + open - 0.001) && !hover.isOpen, "nothing opens before the delay")
        precondition(hover.tick(at: 10 + open) && hover.isOpen, "resting the delay out opens the island")
        precondition(hover.deadline == nil, "an open, hovered island has no clock running")
    }

    static func passThrough() {
        var hover = IslandHover()
        hover.update(Input(inside: true), at: 0)
        hover.update(Input(inside: false), at: open * 0.6)
        precondition(hover.deadline == nil && !hover.tick(at: 5) && !hover.isOpen,
                     "a pointer passing through on its way to the menu bar opens nothing")
        hover.update(Input(inside: true), at: 6)
        precondition(hover.deadline == 6 + open, "coming back starts a fresh delay, none of the old one is kept")
    }

    static func leaving() {
        var hover = opened()
        hover.update(Input(inside: false), at: 20)
        precondition(hover.isOpen && hover.deadline == 20 + close, "leaving starts the close clock")
        hover.update(Input(inside: true), at: 20 + close / 2)
        precondition(hover.isOpen && hover.deadline == nil, "coming back within the close delay cancels it")
        hover.update(Input(inside: false), at: 30)
        precondition(!hover.tick(at: 30 + close - 0.001) && hover.isOpen, "it stays until the delay is out")
        precondition(hover.tick(at: 30 + close) && !hover.isOpen, "then it closes")
        var menu = opened()
        menu.update(Input(inside: false, menuOpen: true), at: 20)
        precondition(menu.isOpen && menu.deadline == nil, "the island's menu keeps the open view where it is")
        var moving = IslandHover()
        moving.update(Input(inside: true, moving: true), at: 0)
        precondition(moving.deadline == nil, "a moving island starts no hover")
        moving.update(Input(inside: true), at: 1)
        precondition(moving.deadline == 1 + open, "the delay starts once the island settles")
    }

    static func buttons() {
        var hover = IslandHover()
        hover.update(Input(inside: true, buttonHeld: true), at: 0)
        precondition(hover.deadline == nil && !hover.tick(at: 9), "dragging across the island opens nothing (H10)")
        hover.update(Input(inside: true), at: 9)
        precondition(hover.deadline == 9 + open, "releasing on the island starts the delay then")
        var drag = opened()
        drag.update(Input(inside: false, buttonHeld: true), at: 20)
        precondition(drag.isOpen && drag.deadline == nil, "dragging out of an open island keeps it open")
        drag.update(Input(inside: false), at: 21)
        precondition(drag.deadline == 21 + close, "the close delay starts at release")
    }

    static func covered() {
        var hover = IslandHover()
        hover.update(Input(inside: true, covered: true), at: 0)
        precondition(hover.deadline == nil && !hover.isOpen, "under the launcher or full screen hover does nothing")
        var open = opened()
        precondition(open.update(Input(inside: true, covered: true), at: 20) && !open.isOpen,
                     "the launcher hotkey closes an open hover view at once (H12)")
        var pinned = opened()
        pinned.togglePin(at: 20)
        pinned.update(Input(inside: false, covered: true), at: 21)
        precondition(!pinned.isOpen && !pinned.isPinned, "the launcher also closes a pinned island")
    }

    static func settingOff() {
        var hover = IslandHover()
        hover.update(Input(inside: true, enabled: false), at: 0)
        precondition(hover.deadline == nil && !hover.tick(at: 60) && !hover.isOpen,
                     "with Open on hover off, resting the pointer opens nothing (H17)")
        var open = opened()
        open.update(Input(inside: true, enabled: false), at: 20)
        precondition(!open.isOpen, "turning it off closes a hover-opened view")
        var pinned = IslandHover()
        pinned.update(Input(enabled: false), at: 0)
        pinned.togglePin(at: 1)
        precondition(pinned.isOpen && pinned.isPinned, "a pin still opens the island with hover off")
        pinned.update(Input(enabled: false), at: 2)
        precondition(pinned.isOpen, "and keeps it open")
    }

    static func pin() {
        var hover = opened()
        hover.togglePin(at: 20)
        precondition(hover.isOpen && hover.isPinned, "Command-P pins the open island")
        hover.update(Input(inside: false), at: 21)
        precondition(hover.deadline == nil && !hover.tick(at: 99) && hover.isOpen,
                     "a pinned island stays open after the pointer leaves")
        hover.togglePin(at: 100)
        precondition(!hover.isPinned && hover.deadline == 100 + close, "unpinning with the pointer away starts the close")
        precondition(hover.tick(at: 100 + close) && !hover.isOpen, "and closes it")
        var closed = IslandHover()
        closed.togglePin(at: 0)
        precondition(closed.isOpen && closed.isPinned, "Command-P opens and pins a closed island")
        closed.dismiss()
        precondition(!closed.isOpen && !closed.isPinned, "Escape or a click outside dismisses a pinned island")
        var escaped = opened()
        escaped.dismiss()
        escaped.update(Input(inside: true), at: 30)
        precondition(escaped.deadline == nil && !escaped.tick(at: 99) && !escaped.isOpen,
                     "Escape under the pointer stays closed while the pointer stays")
        escaped.update(Input(inside: false), at: 100)
        escaped.update(Input(inside: true), at: 101)
        precondition(escaped.tick(at: 101 + IslandHover.openDelay) && escaped.isOpen,
                     "and opens again once the pointer has left and come back")
    }

    static func zone() {
        // A 185 × 32 notch at the top of a 900-point screen with a 32-point menu bar.
        let notch = CGRect(x: 663, y: 868, width: 185, height: 32)
        func hits(_ x: CGFloat, _ y: CGFloat) -> Bool {
            IslandHoverZone.contains(CGPoint(x: x, y: y), shape: notch, menuBarBottom: 868, below: 20, side: 10)
        }
        precondition(hits(755, 890), "the notch itself counts")
        precondition(hits(755, 860) && hits(700, 849), "just below the notch counts, no aiming at its edge (H9)")
        precondition(hits(656, 860) && hits(855, 860), "below the menu bar the zone reaches past each end")
        precondition(!hits(655, 890) && !hits(856, 890), "inside the menu bar the items beside the notch stay its own")
        precondition(hits(755, 900), "the screen's top pixel row over the notch counts (#1000)")
        precondition(!hits(755, 847), "the zone stops 20 points under the menu bar")
        precondition(!hits(652, 860), "and 10 points past each end")
        // A notchless 96 × 24 pill at the top edge of a 30-point menu bar.
        let pill = CGRect(x: 708, y: 876, width: 96, height: 24)
        func pillHits(_ x: CGFloat, _ y: CGFloat) -> Bool {
            IslandHoverZone.contains(CGPoint(x: x, y: y), shape: pill, menuBarBottom: 870, below: 20, side: 10)
        }
        precondition(pillHits(756, 900), "the top row over a top-edge pill counts (#1000)")
        precondition(pillHits(756, 872), "between the pill and the menu bar's lower edge counts")
        precondition(pillHits(756, 855) && !pillHits(756, 849), "the reach is measured from the menu bar's bottom")
        precondition(!pillHits(700, 880), "beside the pill inside the menu bar does not count")
        let open = CGRect(x: 380, y: 480, width: 760, height: 420)
        precondition(IslandHoverZone.contains(CGPoint(x: 400, y: 500), shape: open, menuBarBottom: 870, below: 20,
                                              side: 10), "an open island counts across its whole shape")
    }

    static func content() {
        let ready = IslandStatus(id: "update", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")
        let download = IslandNotice(id: "dl", symbol: "arrow.down.circle", text: "Lecture 04.mp4",
                                    progress: IslandProgress(fraction: 0.42, headline: false))
        func shown(_ top: IslandNotice?, _ statuses: [IslandStatus] = [], glance: Bool = false, level: Bool = false,
                   hovered: Bool = true) -> IslandNotice? {
            IslandHover.notice(top: top, statuses: statuses, glance: glance, level: level, hovered: hovered)
        }
        precondition(shown(download, hovered: false) == download, "unhovered, the pill shows what it showed")
        precondition(shown(download)?.isHeadline == true && shown(download)?.text == "Lecture 04.mp4",
                     "hovering a download brings its title out below a notch (H5)")
        let copied = IslandNotice(id: "c", symbol: "doc.on.clipboard", text: "Copied")
        precondition(shown(copied) == copied, "a showing notice keeps its look while hovered (H6)")
        let status = shown(nil, [IslandStatus(id: "old", symbol: "a", text: nil, label: "Old"), ready])
        precondition(status?.text == "Update ready" && status?.symbol == "arrow.clockwise.circle"
                     && status?.isHeadline == true, "hovering status glyphs names the newest one (H4)")
        precondition(shown(nil, [ready], glance: true) == nil, "a meeting glance opens its own view, not a status (H3)")
        precondition(shown(download, [ready], level: true) == download, "a volume level changes nothing (H7)")
        precondition(shown(nil) == nil, "a bare island shows nothing on hover (H1 with no player)")
    }

    /// Open Agents from the launcher (#1128): the pin waits for the launcher to go, but only `pinWait`.
    static func pinWhenUncovered() {
        let world = FakeWorld()
        let tracker = world.tracker()
        world.input = Input(covered: true)
        tracker.pinWhenUncovered()
        precondition(!tracker.isOpen, "a covered island waits")
        world.now = IslandHoverTracker.pinWait - 0.5
        world.input = Input()
        tracker.refresh()
        precondition(tracker.isOpen && tracker.isPinned && world.opens == [true], "uncovered in time, it pins")
        precondition(world.fromWait == [true] && !tracker.isPinningFromWait, "that open, and only it, is the wait's")
        let late = FakeWorld()
        let missed = late.tracker()
        late.input = Input(covered: true)
        missed.pinWhenUncovered()
        late.now = IslandHoverTracker.pinWait + 0.5
        late.input = Input()
        missed.refresh()
        precondition(!missed.isOpen && !missed.isPinned && late.opens.isEmpty, "uncovered too late, it never pins")
        late.now += 60
        missed.refresh()
        precondition(!missed.isPinned, "and the spent wait pins nothing later")
        missed.pin()
        precondition(missed.isPinned && late.fromWait == [false], "a later click-pin is no command's (#1155)")
    }

    /// Hover open, click to the menu, onto a row, Escape: closing the menu alone must start the close.
    static func menuEscape() {
        let world = FakeWorld()
        let tracker = world.tracker()
        world.move(Input(inside: true))
        world.advance(to: open)
        precondition(tracker.isOpen && world.opens == [true], "resting on the island opens it")
        world.move(Input(inside: true, menuOpen: true), click: true)
        world.move(Input(inside: false, menuOpen: true))
        precondition(tracker.isOpen && world.wakeAt == nil, "on a menu row the open view stays put")
        world.input = Input(inside: false)
        tracker.refresh()
        precondition(world.wakeAt == open + close, "the menu closing alone starts the close clock")
        world.advance(to: open + close)
        precondition(!tracker.isOpen && world.opens == [true, false], "then the island closes with no pointer move")
    }

    static func monitors() {
        let world = FakeWorld()
        let tracker = world.tracker()
        precondition(tracker.isWatching && world.live == 2, "with hover on, both pointer monitors run")
        world.input = Input(enabled: false)
        tracker.refresh()
        precondition(!tracker.isWatching && world.live == 0, "turning Open on hover off removes both monitors")
        tracker.refresh()
        precondition(world.live == 0 && world.installs == 1, "and none come back while it stays off")
        tracker.togglePin()
        precondition(tracker.isOpen && world.live == 2, "a pin with hover off watches for its outside click")
        tracker.togglePin()
        precondition(!tracker.isOpen && world.live == 0, "unpinned with hover off, nothing is watched again")
        world.input = Input()
        tracker.refresh()
        precondition(tracker.isWatching && world.live == 2, "turning it back on starts the monitors again")
    }

    static func pinnedClick() {
        let world = FakeWorld()
        let tracker = world.tracker()
        tracker.togglePin()
        world.move(Input(inside: true), click: true)
        precondition(tracker.isOpen, "a click on the island keeps the pin")
        world.move(Input(inside: false), click: false)
        precondition(tracker.isOpen, "a move outside keeps the pin")
        world.move(Input(inside: false), click: true)
        precondition(!tracker.isOpen && world.opens == [true, false], "a click outside dismisses the pin and says so")
    }

    /// The pointer pushed against the top of the screen over the island, then left alone (#1029, #1000).
    static func topRowRest() {
        let notch = CGRect(x: 663, y: 868, width: 185, height: 32)
        let pill = CGRect(x: 708, y: 876, width: 96, height: 24)
        for (shape, bar) in [(notch, CGFloat(868)), (pill, 870)] {
            let world = FakeWorld()
            let tracker = world.tracker()
            let inside = IslandHoverZone.contains(CGPoint(x: 756, y: 900), shape: shape, menuBarBottom: bar,
                                                  below: 20, side: 10)
            world.move(Input(inside: inside))
            precondition(!tracker.isOpen && world.wakeAt == open, "resting on the top row starts the intent delay")
            world.advance(to: open)
            precondition(tracker.isOpen && world.opens == [true], "and the island opens with no further pointer move")
        }
    }

    /// A primary click opens the island as hover does and holds it, hover on or off (#1029).
    static func primaryClick() {
        for enabled in [true, false] {
            let world = FakeWorld()
            world.input = Input(inside: true, buttonHeld: true, enabled: enabled)
            let tracker = world.tracker()
            tracker.pin()
            precondition(tracker.isOpen && world.opens == [true], "a click opens the island at once")
            tracker.pin()
            precondition(tracker.isOpen && world.opens == [true], "a second click keeps it open")
            world.move(Input(inside: false, enabled: enabled))
            world.advance(to: 60)
            precondition(tracker.isOpen, "a clicked-open island stays after the pointer leaves")
            world.move(Input(inside: false, enabled: enabled), click: true)
            precondition(!tracker.isOpen && world.opens == [true, false], "until a click outside")
        }
        let world = FakeWorld()
        world.input = Input(inside: true, covered: true)
        let tracker = world.tracker()
        tracker.pin()
        precondition(!tracker.isOpen, "under the launcher a click opens nothing")
    }

    /// The wiring the tracker cannot see: which click reaches `pin` and which the menu (#1029).
    static func clickHooks() throws {
        let coordinator = try source("IslandCoordinator.swift")
        guard let start = coordinator.range(of: "backdrop.onOpen = {"),
              let end = coordinator.range(of: "backdrop.onSettle = ") else {
            preconditionFailure("the coordinator wires the island's click")
        }
        let click = coordinator[start.lowerBound..<end.lowerBound]
        precondition(click.contains("self?.hover.pin()\n"), "a primary click opens and pins the island")
        precondition(!click.contains("openMenu") && !click.contains("pillMenu"), "a primary click never shows the island's menu")
        precondition(coordinator.contains("backdrop.onMenu = { [weak self] pill, window in "
            + "self?.pillMenu.toggle(below: pill, in: window) }\n"), "a secondary click shows the island's menu")
        precondition(coordinator.contains("backdrop.canvas.onPointer = { [weak self] in self?.hover.refresh() }\n"),
                     "the island window's tracking area feeds the hover")
        let menu = try source("IslandPillMenu.swift")
        precondition(!menu.contains("Support") && !menu.contains("supportCoordinator"),
                     "the island's menu has no Support Tinycast row")
    }

    /// Each of these changes an input without a pointer event, so each must ask the tracker again.
    static func refreshHooks() throws {
        let coordinator = try source("IslandCoordinator.swift")
        let menu = try source("IslandPillMenu.swift")
        for (text, header) in [(menu, "func hide()"), (coordinator, "@objc private func rebuild()"),
                               (coordinator, "@objc private func modalEnded()")] {
            precondition(body(text, header).contains("hover.refresh()\n"), "\(header) refreshes the hover")
        }
        let space = body(coordinator, "@objc func spaceChanged()")
        guard let written = space.range(of: "onFullScreenSpace = full"),
              let refreshed = space.range(of: "hover.refresh()\n") else {
            preconditionFailure("spaceChanged refreshes the hover")
        }
        precondition(written.upperBound < refreshed.lowerBound, "spaceChanged refreshes after the full-screen write")
        let visibility = body(coordinator, "private func observeVisibility()")
        for line in ["_ = core.isShowingDialog\n", "_ = core.settings.islandOpensOnHover\n",
                     "self.hover.refresh()\n"] {
            precondition(visibility.contains(line), "observeVisibility keeps \(line.dropLast()) (#1003)")
        }
        precondition(coordinator.contains("backdrop.onSettle = { [weak self] in self?.hover.refresh() }\n"),
                     "a settling island refreshes the hover (#1003)")
        let settled = try source("IslandController.swift").split(separator: "\n")
            .filter { $0.contains("didSettle = ") }
        precondition(settled.count == 1 && settled[0].contains("self?.onSettle?()"), "didSettle calls onSettle (#1003)")
        let glance = body(coordinator, "private func showGlance(")
        guard let set = glance.range(of: "controller.glance = "),
              let synced = glance.range(of: "syncExpansion()\n") else {
            preconditionFailure("showGlance sets the glance and syncs the presenter")
        }
        precondition(set.upperBound < synced.lowerBound, "the presenter reads the glance after it is set (#1001)")
        let core = try source("IslandHoverTracker+Core.swift")
        precondition(core.contains("addLocalMonitorForEvents") && core.contains("&& !(event.window is MenuPanel)"),
                     "a click in an own window counts, except on the island's menu")
    }

    static func source(_ name: String) throws -> String {
        try String(contentsOfFile: "Tinycast/Features/Island/Service/" + name, encoding: .utf8)
    }

    /// From `header` to the first line that closes a member at four-space indent.
    static func body(_ text: String, _ header: String) -> String {
        guard let start = text.range(of: header) else { preconditionFailure("\(header) is gone") }
        let rest = text[start.lowerBound...]
        return String(rest[..<(rest.range(of: "\n    }\n")?.upperBound ?? rest.endIndex)])
    }

    static func opened() -> IslandHover {
        var hover = IslandHover()
        hover.update(Input(inside: true), at: 10)
        hover.tick(at: 10 + open)
        precondition(hover.isOpen)
        return hover
    }
}

/// The pointer, clock and monitors as the tracker sees them, advanced by hand.
@MainActor
final class FakeWorld {
    var input = IslandHover.Input()
    var now: TimeInterval = 0
    var opens: [Bool] = []
    /// Per open change, whether the tracker said a command's waited pin made it.
    var fromWait: [Bool] = []
    private weak var made: IslandHoverTracker?
    var installs = 0
    var live = 0
    var wakeAt: TimeInterval?
    private var fire: (@MainActor () -> Void)?
    private var moved: (@MainActor (Bool) -> Void)?

    func tracker() -> IslandHoverTracker {
        let tracker = IslandHoverTracker(world: .init(
            input: { [unowned self] in input },
            now: { [unowned self] in now },
            watch: { [unowned self] handler in
                installs += 1
                live += 2
                moved = handler
                return ["global", "local"]
            },
            unwatch: { [unowned self] _ in
                live -= 1
                if live == 0 { moved = nil }
            },
            wake: { [unowned self] deadline, fire in
                wakeAt = deadline
                self.fire = fire
                return { [unowned self] in wakeAt = nil; self.fire = nil }
            },
            openChanged: { [unowned self] in
                opens.append($0)
                fromWait.append(made?.isPinningFromWait == true)
            }))
        made = tracker
        tracker.start()
        return tracker
    }

    func move(_ next: IslandHover.Input, click: Bool = false) {
        input = next
        guard let moved else { preconditionFailure("the pointer is not being watched") }
        moved(click)
    }

    func advance(to time: TimeInterval) {
        now = time
        guard let wakeAt, wakeAt <= time, let fire else { return }
        self.wakeAt = nil
        self.fire = nil
        fire()
    }
}
