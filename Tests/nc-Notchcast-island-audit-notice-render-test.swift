// notchcast-hosted-only
// notchcast-kit: notchcast-island-audit
import AppKit

@MainActor
@main
struct IslandAuditNoticeRenderTest {
    static func main() {
        IslandAuditRendering.prepare()
        IslandAuditRendering.renderNotices()
        print("PASS rendered island notice audit surfaces to \(IslandAuditRendering.folder.path)")
    }
}

extension IslandAuditRendering {
    static func renderNotices() {
        for notch in [false, true] {
            let form = notch ? "notch" : "island"
            renderArt("10-notice-glyph-\(form)", IslandNoticeArt(
                IslandNotice(id: "a", symbol: "doc.on.clipboard", text: "Copied"), notch: notch, frosted: frosted))
            renderArt("11-notice-installing-\(form)", IslandNoticeArt(
                IslandNotice(id: "b", symbol: "arrow.down.circle", text: "Installing",
                             progress: IslandProgress(fraction: 0.4, headline: false)), notch: notch, frosted: frosted))
            renderArt("12-notice-failed-\(form)", IslandNoticeArt(
                IslandNotice(id: "c", symbol: "exclamationmark.arrow.circlepath", text: "Update failed",
                             isFailure: true, seconds: 4), notch: notch, frosted: frosted))
        }
        for (key, notice) in swatches {
            renderArt("\(key)-island", IslandNoticeArt(notice, notch: false, frosted: frosted))
        }
    }
}
