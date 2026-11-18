import CoreGraphics
import Foundation

/// When resting the pointer on the island opens it and when leaving closes it (#884).
struct IslandHover: Equatable, Sendable {
    /// A pointer crossing the zone on its way to the menu bar spends well under this inside it.
    static let openDelay: TimeInterval = 0.15
    /// Long enough to slip off the edge and back without the island closing under the pointer.
    static let closeDelay: TimeInterval = 0.3

    /// What the pointer and the rest of the app look like at one instant.
    struct Input: Equatable, Sendable {
        var inside = false
        var buttonHeld = false
        /// The launcher, a question, a modal or a full-screen Space owns the top of the screen.
        var covered = false
        /// The island's own menu is open: nothing opens, and an open view stays put.
        var menuOpen = false
        /// The island is still springing, so a new hover waits for it to settle.
        var moving = false
        /// Settings' "Open on hover"; off, only a pin opens the island.
        var enabled = true
    }

    private(set) var input = Input()
    private(set) var isOpen = false
    private(set) var isPinned = false
    private var readySince: TimeInterval?
    private var leftAt: TimeInterval?
    /// Escape closed it under the pointer: hover stays shut until the pointer has left.
    private var dismissed = false

    /// When `tick` next has work to do, or nil when nothing is pending.
    var deadline: TimeInterval? {
        if !isOpen { return readySince.map { $0 + Self.openDelay } }
        return leftAt.map { $0 + Self.closeDelay }
    }

    /// Returns whether `isOpen` changed.
    @discardableResult
    mutating func update(_ next: Input, at now: TimeInterval) -> Bool {
        input = next
        if !next.inside { dismissed = false }
        let was = isOpen
        if next.covered {
            close()
            return was
        }
        if isOpen {
            readySince = nil
            if !isPinned, !next.enabled {
                close()
            } else if isPinned || next.inside || next.buttonHeld || next.menuOpen {
                leftAt = nil
            } else if leftAt == nil {
                leftAt = now
            }
        } else {
            let ready = next.inside && !next.buttonHeld && !next.menuOpen && !next.moving && next.enabled
                && !dismissed
            if !ready { readySince = nil } else if readySince == nil { readySince = now }
        }
        return tick(at: now) || was != isOpen
    }

    /// Runs whichever clock is due; returns whether `isOpen` changed.
    @discardableResult
    mutating func tick(at now: TimeInterval) -> Bool {
        guard let deadline, now >= deadline else { return false }
        if isOpen { close() } else { open() }
        return true
    }

    /// Command-P on an open island page: a pinned island stays until it is dismissed or unpinned.
    mutating func togglePin(at now: TimeInterval) {
        guard !input.covered else { return }
        if isPinned {
            isPinned = false
            update(input, at: now)
        } else {
            open()
            isPinned = true
        }
    }

    /// Escape, a click outside, or the launcher hotkey.
    mutating func dismiss() {
        close()
        dismissed = input.inside
    }

    private mutating func open() {
        isOpen = true
        readySince = nil
        leftAt = nil
    }

    private mutating func close() {
        isOpen = false
        isPinned = false
        readySince = nil
        leftAt = nil
    }
}

/// Where the pointer counts as on the island, in screen points with y up.
enum IslandHoverZone {
    /// Under the menu bar it widens by `side` and reaches `below`; inside it, it keeps to the shape.
    static func contains(_ point: CGPoint, shape: CGRect, menuBarBottom: CGFloat, below: CGFloat,
                         side: CGFloat) -> Bool {
        if shape.contains(point) { return true }
        let column = CGRect(x: shape.minX, y: min(shape.minY, menuBarBottom), width: shape.width,
                            height: shape.maxY - min(shape.minY, menuBarBottom))
        if column.contains(point) { return true }
        let floor = min(shape.minY, menuBarBottom)
        let band = CGRect(x: shape.minX - side, y: floor - below, width: shape.width + 2 * side, height: below)
        return band.contains(point)
    }
}

extension IslandHover {
    /// The notice a hovered pill shows: the top one with its title, else the newest status's name.
    static func notice(top: IslandNotice?, statuses: [IslandStatus], glance: Bool, level: Bool,
                       hovered: Bool) -> IslandNotice? {
        guard hovered, !level else { return top }
        if var top {
            top.progress?.headline = true
            return top
        }
        guard !glance, let status = statuses.last else { return nil }
        return IslandNotice(id: "hover." + status.id, symbol: status.symbol, text: status.label)
    }
}
