// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/UI/IslandTone+Ink.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift Tinycast/Features/Island/Model/IslandPlayer.swift
import AppKit

@main
struct IslandCanvasTest {
    @MainActor static func main() {
        let notch: CGFloat = 200
        let notice = IslandNotice(id: "n", symbol: "doc.on.clipboard", text: "Copied")
        let meeting = MeetingEvent(id: "m", title: "Standup", start: Date(timeIntervalSince1970: 600), end:
            Date(timeIntervalSince1970: 2400), isAllDay: false, isDeclined: false, calendarID: "c",
            calendarName: "Work", calendarColor: nil, calendarItemID: "i", link: nil)
        let glance = IslandGlance(meeting, now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US"))
        let canvas = IslandCanvas()

        let beside = GlanceArt(glance, notch: true, frosted: false)
        let glyph = Double(GlanceArt.glyph(glance.symbol, tone: .white)?.size.width ?? 0)
        precondition(beside.layout.leading == glyph, "Beside a notch the meeting glance is its glyph, never its title")
        precondition(GlanceArt(glance, notch: false, frosted: false).layout.showsTitle, "Without a notch the title stays")

        canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
        precondition(canvas.headline != nil && canvas.glance == nil, "On a notch a text notice is a headline")
        canvas.show(glance: nil, level: nil, notice: nil, statuses: [], expanded: false, notch: notch)
        precondition(canvas.drawnLine != nil, "An ended headline keeps drawing while the island contracts")

        canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
        canvas.show(glance: glance, level: nil, notice: nil, statuses: [], expanded: true, notch: notch)
        precondition(canvas.expansion != nil && canvas.drawnLine == nil,
                     "An ended headline never draws inside the meeting expansion that replaces it")

        canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
        canvas.covered = true
        precondition(canvas.drawnLine == nil, "No line draws under the palette or a report")
        canvas.covered = false

        canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: nil)
        precondition(canvas.headline == nil && canvas.glance is IslandNoticeArt,
                     "Moving to a notchless screen puts the notice back in the pill")
        canvas.show(glance: nil, level: nil, notice: notice, statuses: [], expanded: false, notch: notch)
        precondition(canvas.headline != nil && canvas.glance == nil, "Moving back to a notch headlines it again")

        let ring = IslandNotice(id: "d", symbol: "arrow.down.circle", text: "Guide.pdf",
                                progress: IslandProgress(fraction: 0.29, headline: false))
        canvas.show(glance: nil, level: nil, notice: ring, statuses: [], expanded: false, notch: notch)
        precondition(canvas.headline == nil && canvas.glance is IslandNoticeArt, "A spent headline draws in the wings")

        precondition(IslandNoticeArt.percent(0.29) == "29%" && IslandNoticeArt.percent(0.999) == "99%"
            && IslandNoticeArt.percent(1) == "100%" && IslandNoticeArt.percent(-1) == "0%",
            "The percent is rounded down, never early to 100%, and four characters at most")
        let long = IslandHeadlineArt(IslandNotice(id: "l", symbol: "arrow.down.circle",
            text: "2 of 3: Ultimate Guide to Swift Concurrency on Apple Platforms", progress: IslandProgress(fraction: 0.08)),
            notch: notch, frosted: false)
        let mode = (long.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode
        print("long headline: width \(long.size.width), text \(long.textWidth) of \(ceil(long.text.size().width))")
        precondition(long.size.width <= 320, "A long headline caps the island at 320 pt, not \(long.size.width)")
        precondition(long.textWidth < ceil(long.text.size().width) && mode == .byTruncatingTail,
                     "A long headline truncates its line at the tail")
        let short = IslandHeadlineArt(IslandNotice(id: "s", symbol: "checkmark.circle",
                                                   text: "Downloaded Swift Concurrency.pdf"), notch: notch, frosted: false)
        print("short headline: width \(short.size.width), text \(short.textWidth) of \(ceil(short.text.size().width))")
        precondition(short.textWidth == ceil(short.text.size().width) && short.size.width > notch + Theme.Radius.panel * 2,
                     "A headline under the cap keeps its natural width")
        clicks()
        swatches()
        tones()
        print("Island canvas: headline, fade-out, expansion, cover, notch switch, percent, headline cap, swatch, tone "
            + "and clicks hold")
    }

    static let blue = IslandSwatch(red: 18 / 255, green: 171 / 255, blue: 239 / 255)

    /// Ring, else swatch, else glyph; a failure keeps its red glyph; the swatch takes the glyph's room exactly.
    @MainActor static func swatches() {
        let glyph = IslandNotice(id: "c", symbol: "eyedropper", text: "#12ABEF")
        var swatch = glyph
        swatch.swatch = blue
        let pill = CGRect(x: 0, y: 0, width: 240, height: 32)
        let side = NotchTheme.Typography.islandGlanceNSFont.pointSize + Theme.Spacing.xs
        let cell = CGPoint(x: Theme.Spacing.lg + side / 2, y: pill.midY)
        let centre = color(bitmap(IslandNoticeArt(swatch, notch: false, frosted: false), in: pill), at: cell)
        precondition(near(centre, (18, 171, 239)), "A notice's swatch fills the glyph's cell, not \(centre)")
        precondition(pixels(IslandNoticeArt(swatch, notch: false, frosted: false), in: pill)
            != pixels(IslandNoticeArt(glyph, notch: false, frosted: false), in: pill), "A swatch replaces the glyph")

        var ring = swatch
        ring.progress = IslandProgress(fraction: 0.4, headline: false)
        var bare = ring
        bare.swatch = nil
        precondition(pixels(IslandNoticeArt(ring, notch: false, frosted: false), in: pill)
            == pixels(IslandNoticeArt(bare, notch: false, frosted: false), in: pill),
            "A known fraction draws its ring, never the swatch")
        var failure = swatch
        failure.isFailure = true
        var plainFailure = failure
        plainFailure.swatch = nil
        for frosted in [false, true] {
            precondition(pixels(IslandNoticeArt(failure, notch: false, frosted: frosted), in: pill)
                == pixels(IslandNoticeArt(plainFailure, notch: false, frosted: frosted), in: pill),
                "A failure draws its red glyph, never a swatch")
        }

        for notched in [false, true] {
            precondition(IslandNoticeArt(swatch, notch: notched, frosted: false).layout
                == IslandNoticeArt(glyph, notch: notched, frosted: false).layout,
                "A swatch notice sizes the pill as the glyph one does")
        }
        var long = glyph
        long.text = "Copied #12ABEF"
        var bareSwatch = long
        bareSwatch.symbol = nil
        bareSwatch.swatch = blue
        var textOnly = bareSwatch
        textOnly.swatch = nil
        // A zero notch keeps the notch's minimum width from hiding the indent.
        let wide = IslandHeadlineArt(bareSwatch, notch: 0, frosted: false)
        let plain = IslandHeadlineArt(textOnly, notch: 0, frosted: false)
        precondition(wide.size == IslandHeadlineArt(long, notch: 0, frosted: false).size
            && wide.size.width == plain.size.width + side + Theme.Spacing.sm,
            "A swatch with no symbol still indents the headline by the cell and its gap")
    }

    /// Nil inks a status glyph as text; each tone takes its Theme token in the look it draws on.
    @MainActor static func tones() {
        let pill = CGRect(x: 0, y: 0, width: 240, height: 32)
        let plain = IslandStatus(id: "cpu", symbol: "cpu", text: nil, label: "CPU")
        for frosted in [false, true] {
            let ink = solid(bitmap(IslandStatusArt([plain], notch: false, frosted: frosted), in: pill))
            let text = Theme.Colors.textPrimary.islandInk(frosted: frosted).usingColorSpace(.deviceRGB)!
            precondition(near(ink, rgb(text)), "An untoned glyph is the text ink, not \(ink)")
            for tone in IslandTone.allCases {
                var toned = plain
                toned.tone = tone
                let drawn = solid(bitmap(IslandStatusArt([toned], notch: false, frosted: frosted), in: pill))
                let token = rgb(tone.ink(frosted: frosted).usingColorSpace(.deviceRGB)!)
                precondition(near(drawn, token), "\(tone) on \(frosted ? "Frosted" : "Black") draws \(drawn), "
                    + "not its token \(token)")
            }
        }
        precondition(IslandTone.warning.ink(frosted: true) != IslandTone.warning.ink(frosted: false),
                     "A tone resolves per look")
    }

    typealias RGB = (Int, Int, Int)

    static func rgb(_ color: NSColor) -> RGB {
        (Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()),
         Int((color.blueComponent * 255).rounded()))
    }

    static func near(_ a: RGB, _ b: RGB, by slack: Int = 3) -> Bool {
        abs(a.0 - b.0) <= slack && abs(a.1 - b.1) <= slack && abs(a.2 - b.2) <= slack
    }

    @MainActor static func pixels(_ art: any PillArt, in pill: CGRect) -> Data {
        let rep = bitmap(art, in: pill)
        return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    @MainActor static func bitmap(_ art: any PillArt, in pill: CGRect) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pill.width), pixelsHigh: Int(pill.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        art.draw(in: pill)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func color(_ rep: NSBitmapImageRep, at point: CGPoint) -> RGB {
        rgb(rep.colorAt(x: Int(point.x), y: rep.pixelsHigh - 1 - Int(point.y))!.usingColorSpace(.deviceRGB)!)
    }

    /// The colour of the most opaque pixel, where antialiasing leaves the ink unmixed.
    static func solid(_ rep: NSBitmapImageRep) -> RGB {
        var best: (alpha: CGFloat, color: NSColor)?
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > (best?.alpha ?? 0) else { continue }
                best = (color.alphaComponent, color)
            }
        }
        return best.map { rgb($0.color) } ?? (0, 0, 0)
    }

    /// A primary click opens the island and only a secondary one reaches its menu (#1029).
    @MainActor static func clicks() {
        let canvas = IslandCanvas(frame: CGRect(x: 0, y: 0, width: 100, height: 24))
        canvas.outline = CGPath(rect: canvas.bounds, transform: nil)
        var opens = 0
        var menus = 0
        canvas.canOpen = { true }
        canvas.onOpen = { opens += 1 }
        canvas.onMenu = { menus += 1 }
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: 50, y: 12), modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
                preconditionFailure("no mouse event")
            }
            return event
        }
        canvas.mouseDown(with: event(.leftMouseDown))
        precondition(opens == 1 && menus == 0, "A primary click opens the island and shows no menu")
        canvas.rightMouseDown(with: event(.rightMouseDown))
        canvas.mouseDown(with: event(.leftMouseDown, .control))
        precondition(opens == 1 && menus == 2, "A right click and a Control click show the menu")
        precondition(canvas.accessibilityPerformPress() && opens == 2 && menus == 2, "VoiceOver's press opens it too")
        var pointer = 0
        canvas.onPointer = { pointer += 1 }
        canvas.updateTrackingAreas()
        canvas.updateTrackingAreas()
        let wanted: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        precondition(canvas.trackingAreas.count == 1 && canvas.trackingAreas[0].options == wanted,
                     "The island tracks the pointer in its own window, whichever app is active (#1029)")
        canvas.mouseMoved(with: event(.mouseMoved))
        canvas.mouseEntered(with: event(.mouseMoved))
        canvas.mouseExited(with: event(.mouseMoved))
        precondition(pointer == 3 && opens == 2 && menus == 2, "A tracked enter, move or exit reports the pointer only")
    }
}
