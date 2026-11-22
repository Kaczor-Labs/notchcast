// notchcast-hosted-only
// notchcast-kit: notchcast-island-audit
// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
import AppKit

@MainActor
@main
struct IslandAuditHeadlineRenderTest {
    static func main() {
        IslandAuditRendering.prepare()
        IslandAuditRendering.renderHeadlines()
        print("PASS rendered island headline audit surfaces to \(IslandAuditRendering.folder.path)")
    }
}

extension IslandAuditRendering {
    static func renderHeadlines() {
        renderHeadline("21-headline-failed-notch", IslandHeadlineArt(
            IslandNotice(id: "d", symbol: "exclamationmark.arrow.circlepath", text: "Update failed",
                         isFailure: true, seconds: 4), notch: 200, frosted: frosted))
        for (key, notice) in swatches {
            renderHeadline("21\(key.dropFirst(2))-notch", IslandHeadlineArt(notice, notch: 200, frosted: frosted))
        }

        let ready = IslandStatus(id: "update", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")
        let download = IslandNotice(id: "dl", symbol: "arrow.down.circle", text: "Lecture 04.mp4",
                                    progress: IslandProgress(fraction: 0.42, headline: false))
        func hovered(_ top: IslandNotice?, _ statuses: [IslandStatus]) -> IslandNotice {
            IslandHover.notice(top: top, statuses: statuses, glance: false, level: false, hovered: true)!
        }
        let look = frosted ? "frosted" : "black"
        for notch in [false, true] {
            let form = notch ? "notch" : "nonotch"
            renderNoticeWrap(notch: notch ? notchSize.width : nil) { name, card in
                island(name, width: card.size.width, body: card.size.height,
                       notch: notch, radius: Theme.Radius.panel) { card.draw(in: $0) }
            } pill: { name, art in compact(name, art, notch: notch) }
            compact("884-08-download-\(form)-\(look)", IslandNoticeArt(download, notch: notch, frosted: frosted),
                    notch: notch)
            for (step, top, statuses) in [("07-status", nil, [ready]), ("09-download", download, [])] {
                let notice = hovered(top, statuses)
                if notch {
                    let line = IslandHeadlineArt(notice, notch: notchSize.width, frosted: frosted)
                    island("884-\(step)-hover-\(form)-\(look)", width: line.size.width, body: line.size.height,
                           notch: true, radius: Theme.Radius.panel) { line.draw(in: $0) }
                } else {
                    compact("884-\(step)-hover-\(form)-\(look)",
                            IslandNoticeArt(notice, notch: false, frosted: frosted), notch: false)
                }
            }
        }
    }

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
            IslandNotice(id: "headphones", symbol: "waveform.badge.minus",
                         text: "No headphones with noise control are connected.", isFailure: true),
            IslandNotice(id: "torrent", symbol: "exclamationmark.triangle",
                         text: "<name>: This torrent is already running.", isFailure: true),
            IslandNotice(id: "torrent-long", symbol: "exclamationmark.triangle",
                text: "A Long Linux Distribution Image File.iso: This torrent is already running.", isFailure: true),
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
