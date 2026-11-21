import AppKit

extension NotchcastIslandAuditRenderTest {
    /// The notch headline below the hardware, drawn at the bottom of the grown island.
    static func renderHeadline(_ name: String, _ art: IslandHeadlineArt) {
        let box = CGRect(x: 16, y: 16, width: art.size.width, height: art.size.height)
        writeArt(name, size: CGSize(width: box.width + 32, height: box.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16))
            art.draw(in: box)
        }
    }

    static func renderNoticeWrap(notch: CGFloat?, card: (String, IslandHeadlineArt) -> Void,
                                 pill: (String, any PillArt) -> Void) {
        let notices = [
            IslandNotice(id: "7zz", symbol: "exclamationmark.triangle",
                         text: "7zz is not installed. Install it with: brew install sevenzip", isFailure: true),
            IslandNotice(id: "headphones", symbol: "headphones", text: "No headphones with noise control are connected."),
            IslandNotice(id: "hatchzip", symbol: "exclamationmark.triangle",
                text: "hatchzip is not installed. Install it with: brew install xevrion/tap/hatchzip", isFailure: true),
            IslandNotice(id: "ellipsis", symbol: "doc",
                         text: String(repeating: "Quarterly planning review notes for the whole design team. ", count: 4)),
            IslandNotice(id: "no-mark", text: "No headphones with noise control are connected."),
            IslandNotice(id: "failure", symbol: "exclamationmark.triangle",
                         text: "Could not extract the archive. Check that the destination is writable.", isFailure: true),
            IslandNotice(id: "copied", symbol: "doc.on.clipboard", text: "Copied"),
        ]
        let form = notch == nil ? "nonotch" : "notch"
        let look = frosted ? "frosted" : "black"
        let canvas = IslandCanvas()
        canvas.look = frosted ? .frosted : .black
        canvas.still = true
        for notice in notices {
            let name = "1307-\(notice.id)-\(form)-\(look)"
            canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
            if let headline = canvas.headline {
                card(name, headline)
            } else if let art = canvas.glance {
                pill(name, art)
            }
        }
    }
}
