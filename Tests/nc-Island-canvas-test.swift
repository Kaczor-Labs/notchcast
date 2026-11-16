// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift
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
        print("Island canvas: headline, fade-out, expansion, cover, notch switch and percent hold")
    }
}
