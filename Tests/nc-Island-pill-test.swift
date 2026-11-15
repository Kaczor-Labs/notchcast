// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift
// notchcast-sources: Tinycast/Features/Calendar/Model/*.swift
import Foundation

@main
struct IslandPillTest {
    static func main() {
        rows()
        glance()
        layout()
        print("Island pill: menu rows, glance text and glance widths hold")
    }

    static func rows() {
        let tail: [[PillMenuRow]] = [[.checkForUpdates, .support, .settings], [.quit]]
        precondition(PillMenuRow.sections(clipboard: false, calendar: false, notes: false, carded: false) == tail,
                     "Everything off leaves updates, support, settings and quit")
        precondition(PillMenuRow.sections(clipboard: false, calendar: false, notes: false, carded: true) == tail,
                     "A carded meeting with Calendar off offers no join")
        precondition(PillMenuRow.sections(clipboard: true, calendar: true, notes: true, carded: true) ==
            [[.join, .openInCalendar], [.mySchedule, .clipboardHistory, .showNotes, .createNote, .searchNotes]] + tail,
            "The worst case follows the spec sketch")
        for clipboard in [false, true] {
            for calendar in [false, true] {
                for notes in [false, true] {
                    for carded in [false, true] {
                        let sections = PillMenuRow.sections(
                            clipboard: clipboard, calendar: calendar, notes: notes, carded: carded)
                        let flat = sections.flatMap { $0 }
                        precondition(!sections.contains { $0.isEmpty }, "No empty section draws a stray rule")
                        precondition(Array(sections.suffix(2)) == tail, "Settings and quit always close the menu")
                        precondition(flat.contains(.join) == (calendar && carded))
                        precondition(flat.contains(.openInCalendar) == (calendar && carded))
                        precondition(flat.first == (calendar && carded ? .join : flat.first), "Join leads")
                        precondition(flat.contains(.mySchedule) == calendar)
                        precondition(flat.contains(.clipboardHistory) == clipboard)
                        for row in [PillMenuRow.showNotes, .createNote, .searchNotes] {
                            precondition(flat.contains(row) == notes)
                        }
                        precondition(Set(flat).count == flat.count, "No row twice")
                    }
                }
            }
        }
    }

    static func glance() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let english = Locale(identifier: "en_US")
        let zoom = meeting("Weekly product standup with the whole team", start: start,
                           url: "https://us02web.zoom.us/j/123456789")
        let soon = IslandGlance(zoom, now: start - 4 * 60, locale: english)
        precondition(soon.title == MenuBarSummary.title(zoom.title) && soon.title.count <= MenuBarSummary.titleCap,
                     "The glance title is the menu bar's capped title")
        precondition(soon.title.hasSuffix("…"))
        precondition(soon.countdown == UpcomingWindow.countdown(to: start, now: start - 4 * 60, locale: english))
        precondition(soon.countdown.contains("4"), "The countdown names the minutes: \(soon.countdown)")
        precondition(IslandGlance(zoom, now: start + 30, locale: english).countdown == "Now")
        precondition(soon.symbol == "video.fill", "A video provider shows the camera glyph")
        let generic = meeting("Sync", start: start, url: "https://example.com/room")
        let plain = IslandGlance(generic, now: start - 60, locale: english)
        precondition(plain.title == "Sync" && plain.symbol == "link", "A generic link shows the link glyph")
    }

    static func layout() {
        let notch = IslandGlanceLayout(notch: true, glyph: 12, gap: 6, title: 80, separator: 14, countdown: 50, wing: 140)
        precondition(notch.showsTitle && notch.leading == 98 && notch.trailing == 50,
                     "On a notch the title rides the leading wing and the countdown the trailing one")
        let crowded = IslandGlanceLayout(notch: true, glyph: 12, gap: 6, title: 150, separator: 14, countdown: 50, wing: 140)
        precondition(!crowded.showsTitle && crowded.leading == 12 && crowded.trailing == 50,
                     "A title the wing cannot fit drops, keeping glyph and countdown")
        let line = IslandGlanceLayout(notch: false, glyph: 12, gap: 6, title: 80, separator: 14, countdown: 50, wing: 140)
        precondition(line.showsTitle && line.leading == 81 && line.trailing == 81,
                     "Notchless, one centred line splits evenly across both sides")
        let long = IslandGlanceLayout(notch: false, glyph: 12, gap: 6, title: 300, separator: 14, countdown: 50, wing: 140)
        precondition(!long.showsTitle && long.leading == 34 && long.trailing == 34)
        let edge = IslandGlanceLayout(notch: true, glyph: 12, gap: 6, title: 122, separator: 14, countdown: 50, wing: 140)
        precondition(edge.showsTitle, "A title exactly at the wing still fits")
    }

    static func meeting(_ title: String, start: Date, url: String) -> MeetingEvent {
        let link = MeetingLink.detect(in: url)
        precondition(link != nil, "Synthetic link classifies: \(url)")
        return MeetingEvent(id: title, title: title, start: start, end: start + 1800, isAllDay: false,
                            isDeclined: false, calendarID: "c", calendarName: "Work", calendarColor: nil,
                            calendarItemID: "i", link: link)
    }
}
