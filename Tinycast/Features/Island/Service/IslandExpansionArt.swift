import AppKit

/// Two lines, title over detail, drawn at the bottom of the grown pill: the meeting or a new song.
@MainActor
struct IslandExpansionArt {
    let size: CGSize
    private let glyph: NSImage?
    private let title: NSAttributedString
    private let countdown: NSAttributedString
    private let textWidth: CGFloat
    private let edge = Theme.Spacing.lg
    private let gap = Theme.Spacing.sm

    init(_ glance: IslandGlance, frosted: Bool) {
        self.init(glyph: GlanceArt.glyph(glance.symbol, tone: Theme.Colors.textPrimary.islandInk(frosted: frosted)),
                  title: glance.title, detail: glance.countdown, frosted: frosted)
    }

    /// D16: the cover stands where the meeting shows its glyph.
    init(_ song: IslandNowPlaying, frosted: Bool) {
        self.init(glyph: IslandCover.image(song.artwork, side: IslandSongArt.cell, frosted: frosted),
                  title: song.title, detail: song.artist ?? "", frosted: frosted)
    }

    private init(glyph: NSImage?, title: String, detail: String, frosted: Bool) {
        let font = NotchTheme.Typography.islandGlanceNSFont
        self.glyph = glyph
        self.title = NSAttributedString(string: title, attributes: [.font: font,
            .foregroundColor: Theme.Colors.textPrimary.islandInk(frosted: frosted)])
        countdown = NSAttributedString(string: detail, attributes: [.font: font,
            .foregroundColor: Theme.Colors.textSecondary.islandInk(frosted: frosted)])
        let indent = glyph.map { [gap] in $0.size.width + gap } ?? 0
        let widest = NotchTheme.Size.islandHeadlineMaxWidth - edge * 2 - indent
        textWidth = min(ceil(max(self.title.size().width, countdown.size().width)), widest)
        size = CGSize(width: edge * 2 + indent + textWidth, height: Theme.Spacing.md * 2 + self.title.size().height
                      + Theme.Spacing.xxs + countdown.size().height)
    }

    /// Centred in `area`, so the lines stay put while the pill grows around them.
    func draw(in area: CGRect) {
        let x = area.midX - size.width / 2 + edge
        let top = area.maxY - Theme.Spacing.md - title.size().height
        if let glyph {
            glyph.draw(in: CGRect(x: x, y: top + (title.size().height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height))
        }
        let text = x + (glyph.map { $0.size.width + gap } ?? 0)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        title.draw(with: CGRect(x: text, y: top, width: textWidth, height: title.size().height), options: options)
        let detail = top - Theme.Spacing.xxs - countdown.size().height
        countdown.draw(with: CGRect(x: text, y: detail, width: textWidth, height: countdown.size().height),
                       options: options)
    }
}
