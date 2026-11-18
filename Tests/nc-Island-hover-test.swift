// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
import CoreGraphics
import Foundation

@main
struct IslandHoverTest {
    typealias Input = IslandHover.Input
    static let open = IslandHover.openDelay
    static let close = IslandHover.closeDelay

    static func main() {
        delays()
        passThrough()
        leaving()
        buttons()
        covered()
        settingOff()
        pin()
        zone()
        content()
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
        precondition(!hits(755, 847), "the zone stops 20 points under the menu bar")
        precondition(!hits(652, 860), "and 10 points past each end")
        // A notchless 96 × 24 pill at the top edge of a 30-point menu bar.
        let pill = CGRect(x: 708, y: 876, width: 96, height: 24)
        func pillHits(_ x: CGFloat, _ y: CGFloat) -> Bool {
            IslandHoverZone.contains(CGPoint(x: x, y: y), shape: pill, menuBarBottom: 870, below: 20, side: 10)
        }
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

    static func opened() -> IslandHover {
        var hover = IslandHover()
        hover.update(Input(inside: true), at: 10)
        hover.tick(at: 10 + open)
        precondition(hover.isOpen)
        return hover
    }
}
