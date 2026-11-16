import AppKit

/// A level as the glance's twin: its glyph in a fixed cell, then the track; each side hugs its end.
@MainActor
struct IslandLevelArt: PillArt {
    let layout: IslandGlanceLayout
    let level: IslandLevel
    private let glyph: NSImage?
    /// Fixed, so a glyph swap on repeat never resizes the slots and restarts the pill's spring.
    private let cell = NotchTheme.Size.islandLevelCell
    private let track = NotchTheme.Size.islandLevelTrack
    private let gap = Theme.Spacing.sm
    private let edge = Theme.Spacing.lg

    init(_ level: IslandLevel, notch: Bool) {
        self.level = level
        glyph = GlanceArt.glyph(level.symbol)
        layout = IslandGlanceLayout(notch: notch, glyph: cell, gap: gap, title: 0, separator: 0,
                                    countdown: track, wing: NotchTheme.Size.islandGlanceWing)
    }

    var bandSize: CGSize { CGSize(width: edge * 2 + cell + gap + track, height: cell) }

    func draw(in pill: CGRect) {
        if let glyph {
            let x = pill.minX + edge + (cell - glyph.size.width) / 2
            glyph.draw(in: CGRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width,
                                  height: glyph.size.height))
        }
        let height = Theme.Size.volumeTrackHeight
        let origin = CGPoint(x: pill.maxX - edge - track, y: pill.midY - height / 2)
        let extents = IslandLevelTrack(level, width: track)
        func bar(_ span: ClosedRange<Double>) -> NSBezierPath {
            let rect = CGRect(x: origin.x + span.lowerBound, y: origin.y, width: span.upperBound - span.lowerBound,
                              height: height)
            return NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        }
        NSColor(Theme.Colors.border).setFill()
        bar(extents.track).fill()
        NSColor(Theme.Colors.textSecondary).setStroke()
        for zone in [extents.below, extents.above].compactMap(\.self) {
            let outline = bar(zone)
            outline.lineWidth = Theme.Size.hairline
            outline.stroke()
        }
        NSColor(Theme.Colors.textPrimary).setFill()
        if extents.fill.upperBound > extents.fill.lowerBound { bar(extents.fill).fill() }
    }
}

/// The level in the report slot, for when the palette or a question owns the island.
final class IslandLevelBand: NSView {
    var art: IslandLevelArt? {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(art?.level.label)
            setAccessibilityValue(art?.level.value)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .levelIndicator }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(NotchTheme.Colors.islandSurface).setFill()
        bounds.fill()
        art?.draw(in: bounds)
    }
}
