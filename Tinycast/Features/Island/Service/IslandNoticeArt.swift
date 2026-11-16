import AppKit

@MainActor
struct IslandNoticeArt: PillArt {
    let layout: IslandGlanceLayout
    let notice: IslandNotice
    private let notch: Bool
    private let glyph: NSImage?
    private let text: NSAttributedString
    private let textWidth: CGFloat
    /// Fixed, so a progress notice that turns into a glyph one never resizes the slots.
    private let cell = NotchTheme.Typography.islandGlanceNSFont.pointSize + Theme.Spacing.xs
    private let gap = Theme.Spacing.sm
    private let edge = Theme.Spacing.lg

    init(_ notice: IslandNotice, notch: Bool) {
        self.notice = notice
        self.notch = notch
        glyph = notice.progress == nil ? notice.symbol.flatMap(GlanceArt.glyph) : nil
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text = NSAttributedString(string: notice.text, attributes: [.font: NotchTheme.Typography.islandGlanceNSFont,
            .foregroundColor: NSColor(Theme.Colors.textPrimary), .paragraphStyle: paragraph])
        let wing = NotchTheme.Size.islandGlanceWing
        let room = notch ? wing : wing * 2 - cell - gap
        textWidth = min(ceil(text.size().width), room)
        layout = IslandGlanceLayout(notch: notch, glyph: cell, gap: notch ? 0 : gap, title: 0, separator: 0,
                                    countdown: textWidth, wing: wing)
    }

    func draw(in pill: CGRect) {
        let box = CGRect(x: pill.minX + edge, y: pill.midY - cell / 2, width: cell, height: cell)
        if let progress = notice.progress {
            ring(progress, in: box.insetBy(dx: Theme.Size.hairline, dy: Theme.Size.hairline))
        } else if let glyph {
            glyph.draw(in: CGRect(x: box.midX - glyph.size.width / 2, y: box.midY - glyph.size.height / 2,
                                  width: glyph.size.width, height: glyph.size.height))
        }
        let height = text.size().height
        let x = notch ? pill.maxX - edge - textWidth : box.maxX + gap
        text.draw(with: CGRect(x: x, y: pill.midY - height / 2, width: textWidth, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func ring(_ progress: Double, in box: CGRect) {
        let track = NSBezierPath(ovalIn: box)
        track.lineWidth = Theme.Size.hairline * 2
        NSColor(Theme.Colors.border).setStroke()
        track.stroke()
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: box.midX, y: box.midY), radius: box.width / 2, startAngle: 90,
                      endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = Theme.Size.hairline * 2
        arc.lineCapStyle = .round
        NSColor(Theme.Colors.textPrimary).setStroke()
        arc.stroke()
    }
}

/// The newest status survives a full wing, since the pill's tap acts on it.
@MainActor
struct IslandStatusArt: PillArt {
    let layout: IslandGlanceLayout
    let statuses: [IslandStatus]
    private let notch: Bool
    private let items: [(glyph: NSImage?, text: NSAttributedString?)]
    private let width: CGFloat
    private let gap = Theme.Spacing.sm
    private let edge = Theme.Spacing.lg

    init(_ statuses: [IslandStatus], notch: Bool) {
        self.statuses = statuses
        self.notch = notch
        let attributes: [NSAttributedString.Key: Any] = [.font: NotchTheme.Typography.islandGlanceNSFont,
            .foregroundColor: NSColor(Theme.Colors.textPrimary)]
        var items = statuses.map { status in
            (glyph: GlanceArt.glyph(status.symbol),
             text: status.text.map { NSAttributedString(string: String($0.prefix(4)), attributes: attributes) })
        }
        func span(_ items: [(glyph: NSImage?, text: NSAttributedString?)]) -> CGFloat {
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
    var shown: Int { items.count }
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
