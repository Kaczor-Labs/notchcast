// notchcast-hosted-only
// notchcast-kit: notchcast-island-audit
// notchcast-sources: Tinycast/Features/Notchcast/Threads/Model/*.swift
// notchcast-sources: Tests/nc-Threads-fixtures.swift
import AppKit

/// #1462: each Threads notice and the resting count from made-up waits, in both forms, Black and Frosted.
@MainActor
@main
struct ThreadsNoticeRenderTest {
    static func main() {
        IslandAuditRendering.prepare()
        let fixtures = ThreadsFixtures.self
        let wait = { (row: ThreadsFixtures.Row) in fixtures.document(rows: [row]).waits[0] }
        let single = [("question", fixtures.question), ("door", fixtures.door), ("failed", fixtures.failed),
                      ("approval", fixtures.approval), ("long", fixtures.long)]
            .map { ($0.0, ThreadsPage.notice(wait($0.1))) }
        let together = ThreadsPage.notices([wait(fixtures.question), wait(fixtures.door)])
        precondition(together.count == 1, "two waits arriving together are one notice")
        let notices = single + [("two-together", together[0].notice)]
        let counts = [("count", fixtures.board(rows: [fixtures.question, fixtures.door, fixtures.approval])),
                      ("count-failed", fixtures.board(rows: [fixtures.question, fixtures.door, fixtures.failed]))]
            .map { name, board in
                guard let status = ThreadsPage.status(board) else { preconditionFailure("\(name) has a count") }
                return (name, status)
            }
        var count = 0
        for frosted in [false, true] {
            let canvas = IslandCanvas()
            canvas.look = frosted ? .frosted : .black
            canvas.still = true
            for notch in [nil, IslandAuditRendering.notchSize.width] {
                let suffix = "\(notch == nil ? "island" : "notch")-\(frosted ? "frosted" : "black")"
                for (name, notice) in notices {
                    canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
                    draw("1462-threads-notice-\(name)-\(suffix)", canvas, notch: notch != nil, frosted: frosted)
                    count += 1
                }
                for (name, status) in counts {
                    canvas.show(glance: nil, level: nil, notice: nil, statuses: [status], expanded: false, notch: notch)
                    precondition(canvas.headline == nil, "the count stays beside the notch, never below it")
                    draw("1462-threads-\(name)-\(suffix)", canvas, notch: notch != nil, frosted: frosted)
                    count += 1
                }
            }
        }
        print("PASS rendered \(count) Threads notices and counts to \(IslandAuditRendering.folder.path)")
    }

    /// A notch headline hangs below the hardware; everything else is the compact pill.
    static func draw(_ name: String, _ canvas: IslandCanvas, notch: Bool, frosted: Bool) {
        if let headline = canvas.headline {
            island(name, width: headline.size.width, body: headline.size.height, notch: notch, frosted: frosted) {
                headline.draw(in: $0)
            }
        } else if let art = canvas.glance {
            let width = IslandAuditRendering.compactWidth(art, notch: notch)
            island(name, width: width, body: notch ? 0 : NotchTheme.Size.islandRest.height, notch: notch,
                   frosted: frosted, radius: notch ? 10 : 12,
                   notchLeft: notch ? Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading : nil) {
                art.draw(in: $0)
            }
        } else {
            preconditionFailure("\(name) drew nothing")
        }
    }

    /// `IslandAuditRendering.island` with the look passed in, since the kit reads it once from the environment.
    static func island(_ name: String, width: CGFloat, body: CGFloat, notch: Bool, frosted: Bool,
                       radius: CGFloat = Theme.Radius.panel, notchLeft: CGFloat? = nil,
                       _ draw: @escaping (CGRect) -> Void) {
        let notchSize = IslandAuditRendering.notchSize
        let top = notch ? notchSize.height : 0
        let size = CGSize(width: max(width, notch ? notchSize.width : NotchTheme.Size.islandRest.width) + 64,
                          height: top + body + 32)
        IslandAuditRendering.writeArt(name, size: size) { rect in
            let shape = CGRect(x: 32, y: rect.maxY - top - body, width: size.width - 64, height: top + body)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: shape.minX, y: rect.maxY))
            path.line(to: CGPoint(x: shape.minX, y: shape.minY + radius))
            path.appendArc(withCenter: CGPoint(x: shape.minX + radius, y: shape.minY + radius), radius: radius,
                           startAngle: 180, endAngle: 270)
            path.line(to: CGPoint(x: shape.maxX - radius, y: shape.minY))
            path.appendArc(withCenter: CGPoint(x: shape.maxX - radius, y: shape.minY + radius), radius: radius,
                           startAngle: 270, endAngle: 360)
            path.line(to: CGPoint(x: shape.maxX, y: rect.maxY))
            path.close()
            (frosted ? NSColor.white : IslandAuditRendering.blackDesk).setFill()
            rect.fill()
            NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
            (notch || body > NotchTheme.Size.islandRest.height ? path
                : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2)).fill()
            if notch {
                NSColor.black.setFill()
                CGRect(x: shape.minX + (notchLeft ?? (shape.width - notchSize.width) / 2),
                       y: rect.maxY - notchSize.height, width: notchSize.width, height: notchSize.height).fill()
            }
            draw(notch && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                 : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
        }
    }
}
