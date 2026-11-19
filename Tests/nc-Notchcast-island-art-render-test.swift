// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
import AppKit
import SwiftUI

/// Audit only: renders the island's engine art (pill, notch, level and hover states) offscreen to PNGs,
/// beside `nc-Notchcast-island-audit-render-test`'s SwiftUI surfaces. `NC_AUDIT_RENDERS` names the folder.
@MainActor
@main
struct NotchcastIslandArtRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    /// `NC_AUDIT_LOOK=frosted` renders Frosted on its glass tint over a white wallpaper.
    static let frosted = ProcessInfo.processInfo.environment["NC_AUDIT_LOOK"] == "frosted"

    static func write(_ name: String, _ image: CGImage?) {
        guard let image else { preconditionFailure("\(name) did not render") }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let data else { preconditionFailure("\(name) has no PNG") }
        do {
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// Engine art draws in AppKit into the pill's outline, so it renders the way the canvas does.
    static func renderArt(_ name: String, _ art: some PillArt) {
        let width = art.layout.leading + art.layout.trailing + 2 * Theme.Spacing.lg
        let size = CGSize(width: max(width, NotchTheme.Size.islandRest.width), height: 36)
        let image = NSImage(size: CGSize(width: size.width + 32, height: size.height + 32), flipped: false) { rect in
            let pill = CGRect(x: 16, y: 16, width: size.width, height: size.height)
            paintPill(rect, pill: NSBezierPath(roundedRect: pill, xRadius: size.height / 2, yRadius: size.height / 2))
            art.draw(in: pill)
            return true
        }
        var proposed = CGRect(origin: .zero, size: image.size)
        let scaled = NSImage(size: image.size)
        scaled.addRepresentations(image.representations)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil,
                                  hints: [.ctm: AffineTransform(scale: 2)]))
    }

    /// Black's pill on a grey desk; Frosted's glass tint over a white wallpaper, as the canvas fills it.
    static func paintPill(_ rect: CGRect, pill: NSBezierPath) {
        (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
        rect.fill()
        NSColor(frosted ? NotchTheme.GlassLayer.bar.tint : NotchTheme.Colors.islandSurface).setFill()
        pill.fill()
    }

    static func writeArt(_ name: String, size: CGSize, _ draw: @escaping (CGRect) -> Void) {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 2)]))
    }

    /// The notch headline below the hardware, drawn at the bottom of the grown island.
    static func renderHeadline(_ name: String, _ art: IslandHeadlineArt) {
        let box = CGRect(x: 16, y: 16, width: art.size.width, height: art.size.height)
        writeArt(name, size: CGSize(width: box.width + 32, height: box.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16))
            art.draw(in: box)
        }
    }

    /// The level band in the report slot: on Frosted it must leave the glass under it unpainted.
    static func renderBand(_ name: String, _ art: IslandLevelArt) {
        let band = IslandLevelBand(frame: CGRect(origin: .zero, size: art.bandSize))
        band.art = art
        let box = CGRect(x: 16, y: 16, width: art.bandSize.width, height: art.bandSize.height)
        writeArt(name, size: CGSize(width: box.width + 32, height: box.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(rect: box))
            let image = NSImage(size: box.size, flipped: false) { _ in
                band.draw(band.bounds)
                return true
            }
            image.draw(in: box)
        }
    }

    /// #884's hover states at the screen's top edge: a 185 × 32 notch, or the 96 × 24 pill without one.
    static func renderHover(_ meeting: MeetingEvent) {
        let notchSize = CGSize(width: 185, height: 32)
        let glance = IslandGlance(meeting, now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US"))
        let ready = IslandStatus(id: "update", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")
        let download = IslandNotice(id: "dl", symbol: "arrow.down.circle", text: "Lecture 04.mp4",
                                    progress: IslandProgress(fraction: 0.42, headline: false))
        func hovered(_ top: IslandNotice?, _ statuses: [IslandStatus] = []) -> IslandNotice {
            IslandHover.notice(top: top, statuses: statuses, glance: false, level: false, hovered: true)!
        }
        /// Draws the island hanging from the top edge, `body` tall below the notch, art in that lower part.
        func island(_ name: String, width: CGFloat, body: CGFloat, notch: Bool, radius: CGFloat,
                    notchLeft: CGFloat? = nil, _ draw: @escaping (CGRect) -> Void) {
            let top = notch ? notchSize.height : 0
            let size = CGSize(width: max(width, notch ? notchSize.width : NotchTheme.Size.islandRest.width) + 64,
                              height: top + body + 32)
            writeArt(name, size: size) { rect in
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
                paintPill(rect, pill: notch || body > NotchTheme.Size.islandRest.height ? path
                          : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2))
                if notch {
                    NSColor.black.setFill()
                    CGRect(x: shape.minX + (notchLeft ?? (shape.width - notchSize.width) / 2),
                           y: rect.maxY - notchSize.height,
                           width: notchSize.width, height: notchSize.height).fill()
                }
                draw(notch && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                     : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
            }
        }
        /// The compact pill: content hugs the ends, a notch keeps the middle, as the engine sizes the slots.
        func compactWidth(_ art: some PillArt, notch: Bool) -> CGFloat {
            let inner = notch ? Theme.Spacing.md : 0
            return (notch ? notchSize.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
                + art.layout.trailing
        }
        func compact(_ name: String, _ art: some PillArt, notch: Bool) {
            island(name, width: compactWidth(art, notch: notch), body: notch ? 0 : NotchTheme.Size.islandRest.height,
                   notch: notch, radius: notch ? 10 : 12,
                   notchLeft: Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading) { art.draw(in: $0) }
        }
        let look = frosted ? "frosted" : "black"
        for notch in [false, true] {
            let form = notch ? "notch" : "nonotch"
            let meetingArt = GlanceArt(glance, notch: notch, frosted: frosted)
            compact("884-04-meeting-\(form)-\(look)", meetingArt, notch: notch)
            let expansion = IslandExpansionArt(glance, frosted: frosted)
            island("884-05-meeting-hover-\(form)-\(look)",
                   width: max(expansion.size.width, compactWidth(meetingArt, notch: notch)), body: expansion.size.height,
                   notch: notch, radius: Theme.Radius.panel) { expansion.draw(in: $0) }
            compact("884-06-status-\(form)-\(look)", IslandStatusArt([ready], notch: notch, frosted: frosted),
                    notch: notch)
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

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

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
            renderArt("13-status-\(form)", IslandStatusArt(
                [IslandStatus(id: "u", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")],
                notch: notch, frosted: frosted))
            renderArt("14-level-\(form)", IslandLevelArt(
                IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6),
                notch: notch, frosted: frosted))
            renderArt("14b-level-muted-\(form)", IslandLevelArt(
                IslandLevel(source: "volume", symbol: "speaker.slash.fill", label: "Volume", value: 0),
                notch: notch, frosted: frosted))
            renderArt("14c-level-brightness-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 1,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14d-level-extra-dimming-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: -0.125,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14f-level-darkest-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: -0.25,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14g-level-system-minimum-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 0,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14h-level-brightness-half-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 0.5,
                            range: -0.25...1), notch: notch, frosted: frosted))
        }
        renderArt("14e-level-notch-low", IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.1.fill", label: "Volume", value: 0.31),
            notch: true, frosted: frosted))
        renderHeadline("21-headline-failed-notch", IslandHeadlineArt(
            IslandNotice(id: "d", symbol: "exclamationmark.arrow.circlepath", text: "Update failed",
                         isFailure: true, seconds: 4), notch: 200, frosted: frosted))
        let meeting = MeetingEvent(id: "m", title: "Standup", start: Date(timeIntervalSince1970: 600),
            end: Date(timeIntervalSince1970: 2400), isAllDay: false, isDeclined: false, calendarID: "c",
            calendarName: "Work", calendarColor: nil, calendarItemID: "i", link: nil)
        let expansion = IslandExpansionArt(IslandGlance(meeting, now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US")), frosted: frosted)
        let room = CGRect(x: 16, y: 16, width: expansion.size.width, height: expansion.size.height)
        writeArt("25-meeting-expansion-notch", size: CGSize(width: room.width + 32, height: room.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(roundedRect: room, xRadius: 16, yRadius: 16))
            expansion.draw(in: room)
        }
        renderHover(meeting)
        renderBand("22-level-band", IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6),
            notch: false, frosted: frosted))
        print("PASS rendered island art surfaces to \(folder.path)")
    }
}
