import AppKit

/// A notice in the wings; on a notch only its mark and percent or readout, as its text goes below.
@MainActor
struct IslandNoticeArt: PillArt {
    let layout: IslandGlanceLayout
    let notice: IslandNotice
    let tone: NSColor
    private let notch: Bool
    private let mark: IslandNoticeMark
    private let text: NSAttributedString
    private let textWidth: CGFloat
    private let gap = Theme.Spacing.sm
    private let edge = Theme.Spacing.lg
    private static let failureTones = [false, true].map(Theme.Colors.destructive.islandInk(frosted:))

    static func failureTone(frosted: Bool) -> NSColor { failureTones[frosted ? 1 : 0] }

    init(_ notice: IslandNotice, notch: Bool, frosted: Bool, still: Bool = false) {
        self.notice = notice
        self.notch = notch
        mark = IslandNoticeMark(notice, frosted: frosted, still: still)
        tone = mark.tone
        let readout = notice.progress?.reading
        let words = notch ? readout ?? notice.progress?.fraction.map(Self.percent) ?? "" : notice.line
        text = IslandNoticeMark.line(words, frosted: frosted)
        let wing = NotchTheme.Size.islandGlanceWing
        let room = notch ? wing : wing * 2 - IslandNoticeMark.cell - gap
        textWidth = min(IslandNoticeMark.width(words, readout: readout, frosted: frosted), room)
        // A glyph-only notice still needs a right wing, or the engine draws the notch lopsided.
        let trailing = notch ? max(textWidth, IslandNoticeMark.cell) : textWidth
        layout = IslandGlanceLayout(notch: notch, glyph: IslandNoticeMark.cell, gap: notch ? 0 : gap, title: 0,
                                    separator: 0, countdown: trailing, wing: wing)
    }

    /// Rounded down so the wing never claims 100% early; plain digits keep it to four characters.
    static func percent(_ fraction: Double) -> String {
        "\(Int(floor(min(max(fraction, 0), 1) * 100 + 1e-9)))%"
    }

    func draw(in pill: CGRect) {
        let cell = IslandNoticeMark.cell
        let box = CGRect(x: pill.minX + edge, y: pill.midY - cell / 2, width: cell, height: cell)
        mark.draw(in: box)
        let height = text.size().height
        let x = notch ? pill.maxX - edge - textWidth : box.maxX + gap
        text.draw(with: CGRect(x: x, y: pill.midY - height / 2, width: textWidth, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// A notice on one centred line below the notch, drawn at the bottom of the grown island.
@MainActor
struct IslandHeadlineArt {
    let size: CGSize
    let notice: IslandNotice
    let tone: NSColor
    let text: NSAttributedString
    let textWidth: CGFloat
    private let mark: IslandNoticeMark
    private let indent: CGFloat

    init(_ notice: IslandNotice, notch: CGFloat, frosted: Bool, still: Bool = false) {
        self.notice = notice
        mark = IslandNoticeMark(notice, frosted: frosted, still: still)
        tone = mark.tone
        text = IslandNoticeMark.line(notice.line, frosted: frosted)
        let inset = NotchTheme.Spacing.islandInset
        indent = mark.isEmpty ? 0 : IslandNoticeMark.cell + Theme.Spacing.sm
        let natural = IslandNoticeMark.width(notice.line, readout: notice.progress?.reading, frosted: frosted)
        textWidth = min(natural, NotchTheme.Size.islandHeadlineMaxWidth - inset * 2 - indent)
        let width = max(indent + textWidth + inset * 2, notch + Theme.Radius.panel * 2)
        size = CGSize(width: width, height: ceil(text.size().height) + Theme.Spacing.lg * 2)
    }

    /// Centred in `area`, so the line stays put while the island grows around it.
    func draw(in area: CGRect) {
        let cell = IslandNoticeMark.cell
        let x = area.midX - (indent + textWidth) / 2
        mark.draw(in: CGRect(x: x, y: area.midY - cell / 2, width: cell, height: cell))
        let height = text.size().height
        text.draw(with: CGRect(x: x + indent, y: area.midY - height / 2, width: textWidth, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// What leads a notice: live bars, else its ring while the fraction is known, else swatch or glyph.
@MainActor
private struct IslandNoticeMark {
    /// Fixed, so a progress notice that turns into a glyph one never resizes the slots.
    static let cell = NotchTheme.Typography.islandGlanceNSFont.pointSize + Theme.Spacing.xs
    let tone: NSColor
    private let frosted: Bool
    private let bars: [Double]?
    private let fraction: Double?
    private let swatch: NSColor?
    private let glyph: NSImage?

    init(_ notice: IslandNotice, frosted: Bool, still: Bool) {
        self.frosted = frosted
        tone = notice.isFailure
            ? IslandNoticeArt.failureTone(frosted: frosted) : Theme.Colors.textPrimary.islandInk(frosted: frosted)
        bars = still ? nil : notice.meter.map {
            IslandNotice.bars($0, count: IslandEqualizer.bars, floor: IslandEqualizer.floor)
        }
        fraction = bars == nil ? notice.progress?.fraction : nil
        swatch = bars == nil && fraction == nil && !notice.isFailure
            ? notice.swatch.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } : nil
        glyph = bars == nil && fraction == nil && swatch == nil
            ? notice.symbol.flatMap { [tone] in GlanceArt.glyph($0, tone: tone) } : nil
    }

    var isEmpty: Bool { bars == nil && fraction == nil && swatch == nil && glyph == nil }

    /// A readout is measured by its shape, so the wing moves only when a character comes or goes.
    static func width(_ words: String, readout: String?, frosted: Bool) -> CGFloat {
        ceil(line(readout == nil ? words : IslandProgress.shape(of: words), frosted: frosted).size().width)
    }

    static func line(_ string: String, frosted: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [.font: NotchTheme.Typography.islandGlanceNSFont,
            .foregroundColor: Theme.Colors.textPrimary.islandInk(frosted: frosted), .paragraphStyle: paragraph])
    }

    func draw(in box: CGRect) {
        if let bars {
            meter(bars, in: box)
        } else if let fraction {
            ring(fraction, in: box.insetBy(dx: Theme.Size.hairline, dy: Theme.Size.hairline))
        } else if let swatch {
            let radius = IslandCover.radius
            swatch.setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            IslandCover.edge(in: box, frosted: frosted)
        } else if let glyph {
            glyph.draw(in: CGRect(x: box.midX - glyph.size.width / 2, y: box.midY - glyph.size.height / 2,
                                  width: glyph.size.width, height: glyph.size.height))
        }
    }

    /// The song meter's bars, fed by the caller's levels instead of a clock.
    private func meter(_ bars: [Double], in box: CGRect) {
        let bar = Theme.Spacing.xxs
        let step = (box.width - bar) / Double(max(bars.count - 1, 1))
        tone.setFill()
        for (index, level) in bars.enumerated() {
            let height = max(bar, box.height * level)
            let frame = CGRect(x: box.minX + Double(index) * step, y: box.midY - height / 2, width: bar, height: height)
            NSBezierPath(roundedRect: frame, xRadius: bar / 2, yRadius: bar / 2).fill()
        }
    }

    private func ring(_ progress: Double, in box: CGRect) {
        let track = NSBezierPath(ovalIn: box)
        track.lineWidth = Theme.Size.hairline * 2
        Theme.Colors.border.islandInk(frosted: frosted).setStroke()
        track.stroke()
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: box.midX, y: box.midY), radius: box.width / 2, startAngle: 90,
                      endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = Theme.Size.hairline * 2
        arc.lineCapStyle = .round
        Theme.Colors.textPrimary.islandInk(frosted: frosted).setStroke()
        arc.stroke()
    }
}

/// The newest status survives a full wing, since the pill's tap acts on it.
@MainActor
struct IslandStatusArt: PillArt {
    let layout: IslandGlanceLayout
    let statuses: [IslandStatus]
    private let notch: Bool
    private let items: [(id: String, glyph: NSImage?, text: NSAttributedString?)]
    private let width: CGFloat
    private let gap = Theme.Spacing.sm
    private let edge = Theme.Spacing.lg

    init(_ statuses: [IslandStatus], notch: Bool, frosted: Bool) {
        self.statuses = statuses
        self.notch = notch
        let ink = Theme.Colors.textPrimary.islandInk(frosted: frosted)
        let attributes: [NSAttributedString.Key: Any] = [.font: NotchTheme.Typography.islandGlanceNSFont,
            .foregroundColor: ink]
        var items = statuses.map { status in
            (id: status.id, glyph: GlanceArt.glyph(status.symbol, tone: status.tone?.ink(frosted: frosted) ?? ink),
             text: status.text.map { NSAttributedString(string: String($0.prefix(4)), attributes: attributes) })
        }
        func span(_ items: [(id: String, glyph: NSImage?, text: NSAttributedString?)]) -> CGFloat {
            items.map { ($0.glyph?.size.width ?? 0) + ($0.text.map { Theme.Spacing.xs + $0.size().width } ?? 0) }
                .reduce(0) { $0 == 0 ? $1 : $0 + Theme.Spacing.sm + $1 }
        }
        let wing = NotchTheme.Size.islandGlanceWing
        while items.count > 1, span(items) > (notch ? wing : wing * 2) { items.removeFirst() }
        self.items = items
        width = span(items)
        let line = notch ? width : max(width, NotchTheme.Size.islandRest.width - edge * 2)
        layout = IslandGlanceLayout(notch: notch, glyph: 0, gap: 0, title: 0, separator: 0, countdown: line,
                                    wing: wing)
    }

    #if DEBUG
    var shown: [String] { items.map(\.id) }
    #endif

    func draw(in pill: CGRect) {
        var x = notch ? pill.maxX - edge - width : pill.midX - width / 2
        for item in items {
            if let glyph = item.glyph {
                glyph.draw(in: CGRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width,
                                      height: glyph.size.height))
                x += glyph.size.width
            }
            if let text = item.text {
                x += Theme.Spacing.xs
                text.draw(at: CGPoint(x: x, y: pill.midY - text.size().height / 2))
                x += text.size().width
            }
            x += gap
        }
    }
}
