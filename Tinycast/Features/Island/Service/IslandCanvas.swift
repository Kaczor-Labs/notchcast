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
    var look = IslandLook.black { didSet { if look != oldValue { replay?(self); onAppearanceChange?() } } }
    /// Each art resolves its inks once, so a look flip replays the last `show` to rebuild it.
    private var replay: ((IslandCanvas) -> Void)?
    /// Frosted under Reduce Transparency or Increase Contrast paints its glass solid.
    var solidGlass = false
    var restingKeyline = 0.0
    /// How far past the rest pill the outline has grown, so the line fades with the island, never pops.
    var keylineStrength: Double {
        guard let bounds = outline?.boundingBoxOfPath else { return 0 }
        let height = min(bounds.maxY, self.bounds.height) - bounds.minY - restHeight
        return IslandKeyline.strength(growth: max(bounds.width - restWidth, height), enabled: keylineEnabled,
                                      resting: restingKeyline)
    }
    var keylineWidth: CGFloat { IslandKeyline.width(scale: scale, look: look) }
    /// Resolved against the canvas's own appearance, because the drawing appearance lags a flip.
    var keylineColor: CGColor {
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor(look == .frosted ? NotchTheme.Colors.islandEdge : NotchTheme.Colors.islandKeyline).cgColor
        }
        return color.copy(alpha: color.alpha * keylineStrength) ?? color
    }
    private var surface: Color {
        switch look {
        case .black: NotchTheme.Colors.islandSurface
        case .frosted: solidGlass ? NotchTheme.Colors.islandGlassSolid : NotchTheme.Colors.islandGlassTint
        }
    }
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
    var onOpen: (() -> Void)?
    var onMenu: (() -> Void)?
    var canOpen: (() -> Bool)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let outline, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline)
        context.setFillColor(NSColor(surface).cgColor)
        context.fillPath()
        #if DEBUG
        if look == .frosted, let notch = IslandController.simulatedNotch {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: bounds.midX - notch.width / 2, y: bounds.maxY - notch.height, width: notch.width,
                                height: notch.height))
        }
        #endif
        if keylineStrength > 0 {
            context.saveGState()
            context.addPath(outline)
            context.clip()
            context.addPath(outline)
            context.setStrokeColor(keylineColor)
            context.setLineWidth(2 * keylineWidth)
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
    /// The pointer entered, left or moved over the island window; no global monitor is needed for it (#1029).
    var onPointer: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                                                              .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onPointer?() }
    override func mouseExited(with event: NSEvent) { onPointer?() }
    override func mouseMoved(with event: NSEvent) { onPointer?() }
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

    /// The presenter's order: level, notice, meeting glance, song, then status; a notch grows a headline.
    func show(glance: IslandGlance?, level: IslandLevel?, notice: IslandNotice?, statuses: [IslandStatus],
              expanded: Bool, notch: CGFloat?, song: IslandNowPlaying? = nil, songChange: Bool = false) {
        replay = { $0.show(glance: glance, level: level, notice: notice, statuses: statuses, expanded: expanded,
                           notch: notch, song: song, songChange: songChange) }
        let frosted = look == .frosted
        headline = if let notch, level == nil, let notice, notice.isHeadline {
            IslandHeadlineArt(notice, notch: notch, frosted: frosted)
        } else { nil }
        let notched = notch != nil
        let art: (any PillArt)? = if let level {
            IslandLevelArt(level, notch: notched, frosted: frosted)
        } else if let notice {
            headline == nil ? IslandNoticeArt(notice, notch: notched, frosted: frosted) : nil
        } else if let glance {
            GlanceArt(glance, notch: notched, frosted: frosted)
        } else if let song {
            IslandSongArt(song, notch: notched, frosted: frosted, still: still)
        } else if !statuses.isEmpty {
            IslandStatusArt(statuses, notch: notched, frosted: frosted)
        } else { nil }
        self.glance = art
        expansion = if level != nil || notice != nil { nil } else if let glance {
            expanded ? IslandExpansionArt(glance, frosted: frosted) : nil
        } else if let song, songChange { IslandExpansionArt(song, frosted: frosted) } else { nil }
        if expansion != nil { leaving = nil }
        animate((art as? IslandSongArt)?.animates == true)
    }

    /// Reduce Motion or Show animations off: the meter and the line stand still.
    var still = false {
        didSet { if still != oldValue { replay?(self) } }
    }

    /// The meter and a scrolling line redraw on the display's clock only while they move.
    private var ticker: CADisplayLink?

    func animate(_ wanted: Bool) {
        if wanted, ticker == nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            ticker = link
        } else if !wanted {
            ticker?.invalidate()
            ticker = nil
        }
    }

    @objc private func tick() { needsDisplay = true }
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

    init(_ glance: IslandGlance, notch: Bool, frosted: Bool) {
        self.notch = notch
        let font = NotchTheme.Typography.islandGlanceNSFont
        let primary: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: Theme.Colors.textPrimary.islandInk(frosted: frosted)]
        let secondary: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: Theme.Colors.textSecondary.islandInk(frosted: frosted)]
        glyph = Self.glyph(glance.symbol, tone: Theme.Colors.textPrimary.islandInk(frosted: frosted))
        title = NSAttributedString(string: glance.title, attributes: primary)
        separator = NSAttributedString(string: " · ", attributes: secondary)
        countdown = NSAttributedString(string: glance.countdown, attributes: primary)
        // Beside a notch only the glyph and countdown; the title shows below it on hover (design §10).
        layout = IslandGlanceLayout(notch: notch, glyph: Double(glyph?.size.width ?? 0), gap: notch ? 0 : gap,
            title: notch ? 0 : title.size().width, separator: separator.size().width,
            countdown: countdown.size().width, wing: NotchTheme.Size.islandGlanceWing)
    }

    static func glyph(_ name: String, tone: NSColor) -> NSImage? {
        let symbol = NSImage.SymbolConfiguration(pointSize: NotchTheme.Typography.islandGlanceNSFont.pointSize, weight: .medium)
            .applying(.init(paletteColors: [tone]))
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
        if layout.showsTitle, !notch { place(title) }
        if notch {
            x = pill.maxX - edge - countdown.size().width
            place(countdown)
        } else {
            if layout.showsTitle { place(separator) }
            place(countdown)
        }
    }
}
