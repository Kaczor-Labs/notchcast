import AppKit

/// The loaded song in the wings: cover left, the meter or a pause glyph right; the line only without a notch.
@MainActor
struct IslandSongArt: PillArt {
    let layout: IslandGlanceLayout
    /// The meter or a scrolling line moves, so the canvas redraws on the display's clock.
    let animates: Bool
    private let song: IslandNowPlaying
    private let notch: Bool
    private let cover: NSImage
    /// When this song first showed, so its line scrolls from its own start, not mid-way.
    private let since: CFTimeInterval
    private let ink: NSColor
    private let frosted: Bool
    private let line: NSAttributedString
    private let fit: IslandSongLine
    static let cell = Theme.Spacing.lg + Theme.Spacing.sm
    /// Beside a notch the cover keeps clear of the wing's curved end (D25).
    static let notchEnd = Theme.Spacing.xxxl
    static let pillEnd = Theme.Spacing.xl
    static let gap = Theme.Spacing.md
    static let scrollGap = Theme.Spacing.xxxl
    static let scrollSpeed = 30.0
    static let scrollPause = 1.5

    /// `cover` is `IslandCover.image` for this song, scaled once by the canvas rather than on every frame.
    init(_ song: IslandNowPlaying, notch: Bool, frosted: Bool, still: Bool, cover: NSImage, since: CFTimeInterval = 0) {
        self.song = song
        self.notch = notch
        self.frosted = frosted
        self.cover = cover
        self.since = since
        ink = Theme.Colors.textPrimary.islandInk(frosted: frosted)
        let font = NotchTheme.Typography.islandSongNSFont
        let text = NSMutableAttributedString(string: song.title, attributes: [.font: font, .foregroundColor: ink])
        if let artist = song.artist, !artist.isEmpty {
            text.append(NSAttributedString(string: " · " + artist, attributes: [.font: font,
                .foregroundColor: Theme.Colors.textSecondary.islandInk(frosted: frosted)]))
        }
        line = text
        let wing = song.overflow == .scroll ? NotchTheme.Size.islandGlanceWing : NotchTheme.Size.islandHeadlineMaxWidth
        fit = IslandSongLine(text: notch ? 0 : text.size().width, cap: (wing + Theme.Spacing.lg) * 2 - Self.lineChrome,
                             overflow: song.overflow)
        animates = !still && (song.isPlaying || fit.scrolls)
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

    /// Everything on a pill without a notch but the line: ends, cover, glyph and their gaps.
    private static var lineChrome: Double { (pillEnd + gap + cell) * 2 }

    func draw(in pill: CGRect) {
        let time = animates ? CACurrentMediaTime() - since : 0
        let end = notch ? Self.notchEnd : Self.pillEnd
        let y = pill.midY - Self.cell / 2
        cover.draw(in: CGRect(x: pill.minX + end, y: y, width: Self.cell, height: Self.cell))
        drawGlyph(CGRect(x: pill.maxX - end - Self.cell, y: y, width: Self.cell, height: Self.cell), at: time)
        guard !notch else { return }
        let start = pill.minX + end + Self.cell + Self.gap
        let height = line.size().height
        let box = CGRect(x: start, y: pill.midY - height / 2, width: pill.maxX - end - Self.cell - Self.gap - start,
                         height: height)
        guard fit.scrolls, animates, let context = NSGraphicsContext.current?.cgContext else {
            return line.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let width = line.size().width
        let offset = IslandSongLine.offset(text: width, gap: Self.scrollGap, speed: Self.scrollSpeed,
                                           pause: Self.scrollPause, at: time)
        context.saveGState()
        context.clip(to: box)
        line.draw(at: CGPoint(x: start - offset, y: box.minY))
        line.draw(at: CGPoint(x: start - offset + width + Self.scrollGap, y: box.minY))
        context.restoreGState()
    }

    private func drawGlyph(_ rect: CGRect, at time: Double) {
        guard song.isPlaying else {
            guard let pause = GlanceArt.glyph("pause.fill", tone: ink) else { return }
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

/// A song's cover in the island; a tile with a note while it loads, and a 1 pt inside line on every cover.
@MainActor
enum IslandCover {
    static let radius = NotchTheme.Radius.islandCover

    static func draw(_ cover: NSImage?, in rect: CGRect, frosted: Bool) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let cover {
            cover.draw(in: rect)
        } else {
            NotchTheme.Colors.keyCapFill.islandInk(frosted: frosted).setFill()
            shape.fill()
            let symbol = NSImage.SymbolConfiguration(pointSize: rect.height / 2, weight: .medium)
                .applying(.init(paletteColors: [Theme.Colors.textSecondary.islandInk(frosted: frosted)]))
            if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbol) {
                note.draw(in: CGRect(x: rect.midX - note.size.width / 2, y: rect.midY - note.size.height / 2,
                                     width: note.size.width, height: note.size.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NotchTheme.Colors.islandEdge.islandInk(frosted: frosted).setStroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5,
                                yRadius: radius - 0.5)
        edge.lineWidth = 1
        edge.stroke()
    }

    /// The cover decoded and drawn once at `side` points and `scale` pixels a point, so a frame only blits it.
    static func image(_ data: Data?, side: CGFloat, scale: CGFloat, frosted: Bool) -> NSImage {
        let pixels = Int((side * scale).rounded(.up))
        let image = NSImage(size: CGSize(width: side, height: side))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / side, y: CGFloat(pixels) / side)
        draw(data.flatMap(NSImage.init(data:)), in: CGRect(origin: .zero, size: image.size), frosted: frosted)
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(bitmap)
        return image
    }
}
