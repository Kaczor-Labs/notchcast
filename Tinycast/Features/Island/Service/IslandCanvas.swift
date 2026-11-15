import AppKit

final class IslandCanvas: NSView {
    var outline: CGPath?
    var glance: GlanceArt?
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
        context.setFillColor(NSColor(Theme.Colors.islandSurface).cgColor)
        context.fillPath()
        let bounds = outline.boundingBoxOfPath
        guard let glance else { return }
        let travel = glanceWidth - restWidth
        context.saveGState()
        context.addPath(outline)
        context.clip()
        let grown = abs(travel) < 1 ? 1 : min(max((bounds.width - restWidth) / travel, 0), 1)
        let expanding = min(max((bounds.height - restHeight) / restHeight, 0), 1)
        context.setAlpha(grown * (1 - expanding))
        glance.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                               height: min(bounds.maxY, self.bounds.height) - bounds.minY))
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
}

/// The glance, measured once per text change and drawn inside the pill on every frame.
@MainActor
struct GlanceArt {
    let layout: IslandGlanceLayout
    private let notch: Bool
    private let glyph: NSImage?
    private let title: NSAttributedString
    private let separator: NSAttributedString
    private let countdown: NSAttributedString
    private let gap = Theme.Spacing.sm

    init(_ glance: IslandGlance, notch: Bool) {
        self.notch = notch
        let font = Theme.Typography.islandGlanceNSFont
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Theme.Colors.textPrimary)]
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Theme.Colors.textSecondary)]
        let symbol = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .medium)
            .applying(.init(paletteColors: [NSColor(Theme.Colors.textPrimary)]))
        glyph = NSImage(systemSymbolName: glance.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(symbol)
        title = NSAttributedString(string: glance.title, attributes: primary)
        separator = NSAttributedString(string: " · ", attributes: secondary)
        countdown = NSAttributedString(string: glance.countdown, attributes: primary)
        layout = IslandGlanceLayout(notch: notch, glyph: Double(glyph?.size.width ?? 0), gap: gap,
            title: title.size().width, separator: separator.size().width,
            countdown: countdown.size().width, wing: Theme.Size.islandGlanceWing)
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
