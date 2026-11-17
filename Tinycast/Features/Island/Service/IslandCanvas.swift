import AppKit
import SwiftUI

final class IslandCanvas: NSView {
    var outline: CGPath?
    var glance: (any PillArt)?
    var expansion: IslandExpansionArt?
    var headline: IslandHeadlineArt? {
        didSet { leaving = headline == nil ? oldValue ?? leaving : nil }
    }
    /// Kept while the island contracts, so the line fades out instead of vanishing.
    private var leaving: IslandHeadlineArt?
    /// The palette or a report owns the grown shape, so no notice line draws inside it.
    var covered = false
    var drawnLine: IslandHeadlineArt? { covered ? nil : headline ?? leaving }
    var restWidth: CGFloat = 0
    var restHeight: CGFloat = 1
    var glanceWidth: CGFloat = 0
    var keylineEnabled = true
    var scale: CGFloat = 2
    /// How far past the rest pill the outline has grown, so the line fades with the island, never pops.
    var keylineStrength: Double {
        guard let bounds = outline?.boundingBoxOfPath else { return 0 }
        let height = min(bounds.maxY, self.bounds.height) - bounds.minY - restHeight
        return IslandKeyline.strength(growth: max(bounds.width - restWidth, height), enabled: keylineEnabled)
    }
    /// Resolved against the canvas's own appearance, because the drawing appearance lags a flip.
    var keylineColor: CGColor {
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor(NotchTheme.Colors.islandKeyline).cgColor
        }
        return color.copy(alpha: color.alpha * keylineStrength) ?? color
    }
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
    var onOpen: (() -> Void)?
    var onMenu: (() -> Void)?
    var canOpen: (() -> Bool)?
    /// The art resolves its theme colours while drawing, so they follow this view, not the ambient appearance.
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { paint(dirtyRect) }
    }
    private func paint(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setFillColor(NSColor(NotchTheme.Colors.islandSurface).cgColor)
        context.fillPath()
        if keylineStrength > 0 {
            context.saveGState()
            context.addPath(outline)
            context.clip()
            context.addPath(outline)
            context.setStrokeColor(keylineColor)
            context.setLineWidth(2 * IslandKeyline.width(scale: scale))
            context.strokePath()
            context.restoreGState()
        }
        let bounds = outline.boundingBoxOfPath
        if covered { leaving = nil }
        let line = drawnLine
        guard glance != nil || expansion != nil || line != nil else { return }
        let travel = glanceWidth - restWidth
        context.saveGState()
        context.addPath(outline)
        context.clip()
        let grown = abs(travel) < 1 ? 1 : min(max((bounds.width - restWidth) / travel, 0), 1)
        let open = headline?.size.height ?? expansion?.size.height ?? leaving?.size.height ?? restHeight
        let expanding = min(max((bounds.height - restHeight) / open, 0), 1)
        // A layer, because NSImage.draw resets the context's alpha and glyphs ignored the fade.
        func fade(_ alpha: CGFloat, _ draw: () -> Void) {
            guard alpha > 0 else { return }
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            draw()
            context.endTransparencyLayer()
        }
        if let glance {
            fade(grown * (1 - expanding)) {
                glance.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                       height: min(bounds.maxY, self.bounds.height) - bounds.minY))
            }
        }
        if let expansion {
            fade(expanding) {
                expansion.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                          height: expansion.size.height))
            }
        }
        if let line {
            // Only the outer half of the travel shows the line, so it is gone before the wings return.
            fade(min(max(expanding * 2 - 1, 0), 1)) {
                line.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: line.size.height))
            }
        }
        if expanding == 0 { leaving = nil }
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

    /// The presenter's order: level, notice, meeting glance, then status; a notch grows a headline.
    func show(glance: IslandGlance?, level: IslandLevel?, notice: IslandNotice?, statuses: [IslandStatus],
              expanded: Bool, notch: CGFloat?) {
        headline = if let notch, level == nil, let notice, notice.isHeadline {
            IslandHeadlineArt(notice, notch: notch)
        } else { nil }
        let notched = notch != nil
        let art: (any PillArt)? = if let level {
            IslandLevelArt(level, notch: notched)
        } else if let notice {
            headline == nil ? IslandNoticeArt(notice, notch: notched) : nil
        } else if let glance {
            GlanceArt(glance, notch: notched)
        } else if !statuses.isEmpty {
            IslandStatusArt(statuses, notch: notched)
        } else { nil }
        self.glance = art
        expansion = level == nil && notice == nil && expanded ? glance.map(IslandExpansionArt.init) : nil
        if expansion != nil { leaving = nil }
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
    private let glyph: IslandGlyph?
    private let title: NSAttributedString
    private let separator: NSAttributedString
    private let countdown: NSAttributedString
    private let gap = Theme.Spacing.sm

    init(_ glance: IslandGlance, notch: Bool) {
        self.notch = notch
        let font = NotchTheme.Typography.islandGlanceNSFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        glyph = IslandGlyph(glance.symbol)
        title = NSAttributedString(string: glance.title, attributes: attributes)
        separator = NSAttributedString(string: " · ", attributes: attributes)
        countdown = NSAttributedString(string: glance.countdown, attributes: attributes)
        layout = IslandGlanceLayout(notch: notch, glyph: Double(glyph?.size.width ?? 0), gap: gap,
            title: title.size().width, separator: separator.size().width,
            countdown: countdown.size().width, wing: NotchTheme.Size.islandGlanceWing)
    }

    /// `pill` is the visible part of the outline; content hugs its ends, as the slots were sized.
    func draw(in pill: CGRect) {
        let edge = Theme.Spacing.lg
        var x = pill.minX + edge
        func place(_ text: NSAttributedString, _ ink: Color) {
            text.inked(ink).draw(at: CGPoint(x: x, y: pill.midY - text.size().height / 2))
            x += text.size().width
        }
        if let glyph {
            glyph.draw(in: CGRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width,
                                  height: glyph.size.height))
            x += glyph.size.width + gap
        }
        if layout.showsTitle { place(title, Theme.Colors.textPrimary) }
        if notch {
            x = pill.maxX - edge - countdown.size().width
            place(countdown, Theme.Colors.textPrimary)
        } else {
            if layout.showsTitle { place(separator, Theme.Colors.textSecondary) }
            place(countdown, Theme.Colors.textPrimary)
        }
    }
}

/// A symbol whose palette tone is a theme token, tinted when drawn so a Dark/Light flip repaints it.
@MainActor
final class IslandGlyph {
    let size: CGSize
    private let name: String
    private let tone: Color
    private var tinted: [Bool: NSImage] = [:]

    init?(_ name: String, tone: Color = Theme.Colors.textPrimary) {
        guard let image = IslandGlyph.image(name, tone: tone, dark: true) else { return nil }
        self.name = name
        self.tone = tone
        size = image.size
        tinted[true] = image
    }

    func draw(in rect: CGRect) {
        let dark = NSAppearance.currentDrawing().isDark
        if tinted[dark] == nil { tinted[dark] = Self.image(name, tone: tone, dark: dark) }
        tinted[dark]?.draw(in: rect)
    }

    private static func image(_ name: String, tone: Color, dark: Bool) -> NSImage? {
        var ink = NSColor.clear
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            ink = NSColor(cgColor: NSColor(tone).cgColor) ?? .clear
        }
        let size = NotchTheme.Typography.islandGlanceNSFont.pointSize
        let symbol = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(.init(paletteColors: [ink]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbol)
    }
}

extension NSAttributedString {
    /// The colour resolves now, against the drawing appearance; a string that carried it would freeze it.
    func inked(_ ink: Color) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: self)
        copy.addAttribute(.foregroundColor, value: NSColor(ink), range: NSRange(location: 0, length: length))
        return copy
    }
}
