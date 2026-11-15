import AppKit

/// The meeting glance on two lines, title over countdown, drawn at the bottom of the grown pill.
@MainActor
struct IslandExpansionArt {
    let size: CGSize
    private let glyph: NSImage?
    private let title: NSAttributedString
    private let countdown: NSAttributedString
    private let edge = Theme.Spacing.lg
    private let gap = Theme.Spacing.sm

    init(_ glance: IslandGlance) {
        let font = NotchTheme.Typography.islandGlanceNSFont
        glyph = GlanceArt.glyph(glance.symbol)
        title = NSAttributedString(string: glance.title,
                                   attributes: [.font: font, .foregroundColor: NSColor(Theme.Colors.textPrimary)])
        countdown = NSAttributedString(string: glance.countdown,
                                       attributes: [.font: font, .foregroundColor: NSColor(Theme.Colors.textSecondary)])
        let indent = glyph.map { [gap] in $0.size.width + gap } ?? 0
        size = CGSize(width: edge * 2 + indent + max(title.size().width, countdown.size().width),
                      height: Theme.Spacing.md * 2 + title.size().height + Theme.Spacing.xxs + countdown.size().height)
    }

    /// `area` is as wide as the pill and as tall as `size`; the lines stay centred as the pill grows.
    func draw(in area: CGRect) {
        let x = area.midX - size.width / 2 + edge
        let top = area.maxY - Theme.Spacing.md - title.size().height
        if let glyph {
            glyph.draw(in: CGRect(x: x, y: top + (title.size().height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height))
        }
        let text = x + (glyph.map { $0.size.width + gap } ?? 0)
        title.draw(at: CGPoint(x: text, y: top))
        countdown.draw(at: CGPoint(x: text, y: top - Theme.Spacing.xxs - countdown.size().height))
    }
}
