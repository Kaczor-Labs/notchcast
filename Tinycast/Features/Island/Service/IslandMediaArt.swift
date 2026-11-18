import AppKit

/// The loaded song in the wings: cover left, the meter or a pause glyph right; the line only without a notch.
@MainActor
struct MediaGlanceArt: PillArt {
    let layout: IslandGlanceLayout
    let animates: Bool
    private let media: IslandMedia
    private let notch: Bool
    private let cover: NSImage?
    private let ink: NSColor
    private let edgeInk: NSColor
    private let tileFill: NSColor
    private let line: NSAttributedString
    private let fit: IslandMediaLine
    static let cell = Theme.Spacing.lg + Theme.Spacing.sm
    /// Beside a notch the cover keeps `md` from the wing's curved end (D25).
    static let notchEnd = Theme.Spacing.xxxl
    static let pillEnd = Theme.Spacing.xl
    static let gap = Theme.Spacing.md
    static let scrollGap = Theme.Spacing.xxxl
    static let scrollSpeed = 30.0
    static let scrollPause = 1.5

    init(_ media: IslandMedia, notch: Bool, frosted: Bool, reducedMotion: Bool) {
        self.media = media
        self.notch = notch
        cover = media.artwork.flatMap(NSImage.init(data:))
        ink = Theme.Colors.textPrimary.islandInk(frosted: frosted)
        edgeInk = NotchTheme.Colors.islandEdge.islandInk(frosted: frosted)
        tileFill = NotchTheme.Colors.keyCapFill.islandInk(frosted: frosted)
        let font = NotchTheme.Typography.islandGlanceNSFont
        let text = NSMutableAttributedString(string: media.title, attributes: [.font: font, .foregroundColor: ink])
        if !media.subtitle.isEmpty {
            text.append(NSAttributedString(string: " · " + media.subtitle, attributes: [.font: font,
                .foregroundColor: Theme.Colors.textSecondary.islandInk(frosted: frosted)]))
        }
        line = text
        let wing = media.overflow == .scroll ? NotchTheme.Size.islandGlanceWing : NotchTheme.Size.islandHeadlineMaxWidth
        let cap = (wing + Theme.Spacing.lg) * 2 - Self.lineChrome
        fit = IslandMediaLine(text: notch ? 0 : text.size().width, cap: cap, overflow: media.overflow)
        animates = !reducedMotion && (media.isPlaying || fit.scrolls)
        if notch {
            let slot = Self.cell + Self.notchEnd - Theme.Spacing.lg
            layout = IslandGlanceLayout(notch: true, glyph: slot, gap: 0, title: 0, separator: 0, countdown: slot,
                                        wing: NotchTheme.Size.islandGlanceWing)
        } else {
            let content = Self.cell * 2 + Self.gap * 2 + fit.width + (Self.pillEnd - Theme.Spacing.lg) * 2
            layout = IslandGlanceLayout(notch: false, glyph: 0, gap: 0, title: 0, separator: 0, countdown: content,
                                        wing: .infinity)
        }
    }

    /// Everything on a notchless pill but the line: ends, cover, glyph and their gaps.
    private static var lineChrome: Double { (pillEnd + gap + cell) * 2 }

    func draw(in pill: CGRect) {
        let time = animates ? CACurrentMediaTime() : 0
        let end = notch ? Self.notchEnd : Self.pillEnd
        let y = pill.midY - Self.cell / 2
        drawCover(CGRect(x: pill.minX + end, y: y, width: Self.cell, height: Self.cell))
        drawGlyph(CGRect(x: pill.maxX - end - Self.cell, y: y, width: Self.cell, height: Self.cell), at: time)
        guard !notch else { return }
        let start = pill.minX + end + Self.cell + Self.gap
        let room = pill.maxX - end - Self.cell - Self.gap - start
        let height = line.size().height
        let box = CGRect(x: start, y: pill.midY - height / 2, width: room, height: height)
        guard fit.scrolls, let context = NSGraphicsContext.current?.cgContext else {
            return line.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let width = line.size().width
        let offset = IslandMediaLine.offset(text: width, gap: Self.scrollGap, speed: Self.scrollSpeed,
                                            pause: Self.scrollPause, at: time)
        context.saveGState()
        context.clip(to: box)
        line.draw(at: CGPoint(x: start - offset, y: box.minY))
        line.draw(at: CGPoint(x: start - offset + width + Self.scrollGap, y: box.minY))
        context.restoreGState()
    }

    private func drawCover(_ rect: CGRect) {
        MediaCover.draw(cover, in: rect, radius: Theme.Spacing.xs, fill: tileFill, edge: edgeInk, ink: ink)
    }

    private func drawGlyph(_ rect: CGRect, at time: Double) {
        guard media.isPlaying else {
            let symbol = NSImage.SymbolConfiguration(pointSize: NotchTheme.Typography.islandGlanceNSFont.pointSize,
                                                     weight: .medium).applying(.init(paletteColors: [ink]))
            guard let pause = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbol) else { return }
            return pause.draw(in: CGRect(x: rect.midX - pause.size.width / 2, y: rect.midY - pause.size.height / 2,
                                         width: pause.size.width, height: pause.size.height))
        }
        let levels = IslandEqualizer.levels(at: time, playing: true)
        let bar = Theme.Spacing.xxs
        let step = (rect.width - bar) / Double(levels.count - 1)
        ink.setFill()
        for (index, level) in levels.enumerated() {
            let height = max(bar, rect.height * level)
            let frame = CGRect(x: rect.minX + Double(index) * step, y: rect.midY - height / 2, width: bar,
                               height: height)
            NSBezierPath(roundedRect: frame, xRadius: bar / 2, yRadius: bar / 2).fill()
        }
    }
}

/// D16: a new song below the notch, its cover where the meeting shows its glyph.
@MainActor
enum MediaCover {
    /// The cover, or a tile with a note while it loads; a 1 pt inside line keeps dark covers on black (D21).
    static func draw(_ cover: NSImage?, in rect: CGRect, radius: CGFloat, fill: NSColor, edge: NSColor,
                     ink: NSColor) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let cover {
            cover.draw(in: rect)
        } else {
            fill.setFill()
            shape.fill()
            let symbol = NSImage.SymbolConfiguration(pointSize: rect.height / 2, weight: .medium)
                .applying(.init(paletteColors: [ink]))
            if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbol) {
                note.draw(in: CGRect(x: rect.midX - note.size.width / 2, y: rect.midY - note.size.height / 2,
                                     width: note.size.width, height: note.size.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        edge.setStroke()
        let line = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5,
                                yRadius: radius - 0.5)
        line.lineWidth = 1
        line.stroke()
    }

    /// The cover as one image the size of the title line, for the shipped two-line expansion.
    static func image(_ data: Data?, side: CGFloat, frosted: Bool) -> NSImage {
        let cover = data.flatMap(NSImage.init(data:))
        let fill = NotchTheme.Colors.keyCapFill.islandInk(frosted: frosted)
        let ink = Theme.Colors.textPrimary.islandInk(frosted: frosted)
        return NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            draw(cover, in: rect, radius: Theme.Spacing.xs, fill: fill, edge: NotchTheme.Colors.islandEdge.islandInk(frosted: frosted),
                 ink: ink)
            return true
        }
    }
}
