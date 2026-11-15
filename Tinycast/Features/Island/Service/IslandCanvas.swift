import AppKit

final class IslandCanvas: NSView {
    var outline: CGPath?
    var glance: (any PillArt)?
    var expansion: IslandExpansionArt?
    var restWidth: CGFloat = 0
    var restHeight: CGFloat = 1
    var glanceWidth: CGFloat = 0
    var onOpen: (() -> Void)?
    var onMenu: (() -> Void)?
    var canOpen: (() -> Bool)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setFillColor(NSColor(NotchTheme.Colors.islandSurface).cgColor)
        context.fillPath()
        let bounds = outline.boundingBoxOfPath
        guard let glance else { return }
        let travel = glanceWidth - restWidth
        context.saveGState()
        context.addPath(outline)
        context.clip()
        let grown = abs(travel) < 1 ? 1 : min(max((bounds.width - restWidth) / travel, 0), 1)
        let expanding = min(max((bounds.height - restHeight) / restHeight, 0), 1)
        // A layer, because NSImage.draw resets the context's alpha and glyphs ignored the fade.
        func fade(_ alpha: CGFloat, _ draw: () -> Void) {
            guard alpha > 0 else { return }
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            draw()
            context.endTransparencyLayer()
        }
        fade(grown * (1 - expanding)) {
            glance.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                   height: min(bounds.maxY, self.bounds.height) - bounds.minY))
        }
        if let expansion {
            fade(expanding) {
                expansion.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                          height: expansion.size.height))
            }
        }
        context.restoreGState()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        outline?.contains(point) == true ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard canOpen?() == true, outline?.contains(convert(event.locationInWindow, from: nil)) == true else { return }
        if !event.modifierFlags.isDisjoint(with: [.control, .option]) { onMenu?() } else { onOpen?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard canOpen?() == true, outline?.contains(convert(event.locationInWindow, from: nil)) == true else { return }
        onMenu?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard canOpen?() == true, let onOpen else { return false }
        onOpen()
        return true
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard canOpen?() == true, let onMenu else { return false }
        onMenu()
        return true
    }

    /// A level outranks the meeting glance while it dwells.
    func show(glance: IslandGlance?, level: IslandLevel?, expanded: Bool, notch: Bool) {
        self.glance = level.map { IslandLevelArt($0, notch: notch) } ?? glance.map { GlanceArt($0, notch: notch) }
        expansion = level == nil && expanded ? glance.map(IslandExpansionArt.init) : nil
        setAccessibilityValue(level.map { "\($0.label), \($0.value.formatted(.percent))" }
            ?? glance.map { "\($0.title), \($0.countdown)" })
    }
}

/// What the resting pill draws in its compact slots, measured once and drawn on every frame.
@MainActor
protocol PillArt {
    var layout: IslandGlanceLayout { get }
    func draw(in pill: CGRect)
}

/// The glance, measured once per text change and drawn inside the pill on every frame.
@MainActor
struct GlanceArt: PillArt {
    let layout: IslandGlanceLayout
    private let notch: Bool
    private let glyph: NSImage?
    private let title: NSAttributedString
    private let separator: NSAttributedString
    private let countdown: NSAttributedString
    private let gap = Theme.Spacing.sm

    init(_ glance: IslandGlance, notch: Bool) {
        self.notch = notch
        let font = NotchTheme.Typography.islandGlanceNSFont
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Theme.Colors.textPrimary)]
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Theme.Colors.textSecondary)]
        glyph = Self.glyph(glance.symbol)
        title = NSAttributedString(string: glance.title, attributes: primary)
        separator = NSAttributedString(string: " · ", attributes: secondary)
        countdown = NSAttributedString(string: glance.countdown, attributes: primary)
        layout = IslandGlanceLayout(notch: notch, glyph: Double(glyph?.size.width ?? 0), gap: gap,
            title: title.size().width, separator: separator.size().width,
            countdown: countdown.size().width, wing: NotchTheme.Size.islandGlanceWing)
    }

    static func glyph(_ name: String) -> NSImage? {
        let symbol = NSImage.SymbolConfiguration(pointSize: NotchTheme.Typography.islandGlanceNSFont.pointSize, weight: .medium)
            .applying(.init(paletteColors: [NSColor(Theme.Colors.textPrimary)]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbol)
    }

    /// `pill` is the visible part of the outline; content hugs its ends, as the slots were sized.
    func draw(in pill: CGRect) {
        let edge = Theme.Spacing.lg
        var x = pill.minX + edge
        func place(_ text: NSAttributedString) {
            text.draw(at: CGPoint(x: x, y: pill.midY - text.size().height / 2))
            x += text.size().width
        }
        if let glyph {
            glyph.draw(in: CGRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width,
                                  height: glyph.size.height))
            x += glyph.size.width + gap
        }
        if layout.showsTitle { place(title) }
        if notch {
            x = pill.maxX - edge - countdown.size().width
            place(countdown)
        } else {
            if layout.showsTitle { place(separator) }
            place(countdown)
        }
    }
}
