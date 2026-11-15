import Foundation

/// The pill's secondary-click menu, one section per inner array; menubar spec §2.2.
enum PillMenuRow: Equatable, Sendable {
    case join, openInCalendar
    case mySchedule, clipboardHistory, showNotes, createNote, searchNotes
    case checkForUpdates, support, settings
    case quit

    static func sections(clipboard: Bool, calendar: Bool, notes: Bool, carded: Bool) -> [[PillMenuRow]] {
        var features: [PillMenuRow] = calendar ? [.mySchedule] : []
        if clipboard { features.append(.clipboardHistory) }
        if notes { features += [.showNotes, .createNote, .searchNotes] }
        let meeting: [PillMenuRow] = calendar && carded ? [.join, .openInCalendar] : []
        return [meeting, features, [.checkForUpdates, .support, .settings], [.quit]].filter { !$0.isEmpty }
    }
}

/// The resting pill's meeting line: the launcher card's twin, never a join; menubar spec §3.
struct IslandGlance: Equatable, Sendable {
    let title: String
    let countdown: String
    let symbol: String

    init(_ meeting: MeetingEvent, now: Date, locale: Locale) {
        title = MenuBarSummary.title(meeting.title)
        countdown = UpcomingWindow.countdown(to: meeting.start, now: now, locale: locale)
        symbol = (meeting.link?.provider ?? .generic).sfSymbol
    }
}

/// How wide each side of the pill grows for a glance, from widths the caller measured.
struct IslandGlanceLayout: Equatable, Sendable {
    let showsTitle: Bool
    /// Content left and right of the sensor; a notchless pill splits one line evenly across both.
    let leading: Double
    let trailing: Double

    /// `separator` is the " · " a notchless line puts between title and countdown.
    init(notch: Bool, glyph: Double, gap: Double, title: Double, separator: Double, countdown: Double,
         wing: Double) {
        if notch {
            let withTitle = glyph + gap + title
            showsTitle = withTitle <= wing
            leading = showsTitle ? withTitle : glyph
            trailing = countdown
            return
        }
        let withTitle = glyph + gap + title + separator + countdown
        showsTitle = withTitle / 2 <= wing
        let line = showsTitle ? withTitle : glyph + gap + countdown
        leading = line / 2
        trailing = line / 2
    }
}
