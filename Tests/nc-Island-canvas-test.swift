// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
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
        print("Island canvas: headline, fade-out, expansion, cover, notch switch, percent, headline cap and clicks hold")
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
    }
}
