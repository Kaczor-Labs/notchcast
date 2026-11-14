// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Settings/AppAppearance.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastIslandPins.swift
// notchcast-reads: Tinycast/Features/Settings/AppSettings.swift
// notchcast-reads: Tinycast/Features/Settings/Panes/GeneralSettingsView.swift
// notchcast-reads: Tinycast/Features/Notes/Settings/NotesSettingsView.swift
// notchcast-reads: Tinycast/Features/Calendar/Settings/CalendarSettingsView.swift
// notchcast-reads: Tinycast/Features/Backup/Settings/RaycastImportSelection.swift
import AppKit
import Foundation

@main
struct HiddenFeaturesTest {
    static func main() {
        let visible = SettingsSection.allCases.flatMap(\.tabs)
        precondition(NotchcastHidden.tabs == [.extensions])
        precondition(!visible.contains(.extensions), "Extensions stays out of the sidebar")
        precondition(SettingsTab(slug: "extensions") == nil, "settings/extensions opens nothing")
        precondition(!SettingsSearchCatalog.entries.contains { $0.tab == .extensions })
        for tab in [SettingsTab.appleShortcuts, .backup, .about, .fallbacks] {
            precondition(visible.contains(tab), "Stock tab stays visible: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == tab, "settings/\(tab.slug) still opens")
            precondition(SettingsSearchCatalog.entries.contains { $0.tab == tab })
        }

        let titles = ["Appearance", "Follow the cursor across displays", "Drag to move the launcher"]
        let menuBarTitles = [
            "Show in menu bar", "Show in Menu Bar", "Calendar in Menu Bar", "Show Upcoming Events",
            "Only show events with meetings", "Hide when there are no upcoming events", "Hide Current Event",
        ]
        precondition(NotchcastHidden.rows == Set(titles + menuBarTitles))
        for title in titles + menuBarTitles {
            precondition(
                !SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) },
                "Search omits the hidden row: \(title)")
        }
        for title in ["Show animations", "Interface size", "Window mode", "Days to Show"] {
            precondition(
                SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) },
                "Search keeps the stock row: \(title)")
        }
        precondition(SettingsSearchCatalog.entries.contains { $0.tab == .general })

        precondition(NotchcastIslandPins.appearance == .dark, "The island is black: appearance is dark")
        precondition(NotchcastIslandPins.appearance.nsAppearance?.name == .darkAqua)
        precondition(!NotchcastIslandPins.paletteDraggable, "The panel is never dragged, so never snaps")
        precondition(NotchcastIslandPins.openOnCursorScreen)
        precondition(!NotchcastIslandPins.remembersPalettePosition)

        let settings = source("Tinycast/Features/Settings/AppSettings.swift")
        for pin in ["appearance", "openOnCursorScreen", "paletteDraggable"] {
            precondition(
                settings.contains("var \(pin): ") && settings.contains("get { NotchcastIslandPins.\(pin) }"),
                "AppSettings.\(pin) reads its pin")
            precondition(!settings.contains("\(pin) = defaults"), "AppSettings.\(pin) ignores persisted values")
        }
        precondition(
            settings.contains("guard NotchcastIslandPins.remembersPalettePosition else { return nil }"),
            "A stored panel position is never restored")
        let general = source("Tinycast/Features/Settings/Panes/GeneralSettingsView.swift")
        precondition(
            general.components(separatedBy: ".notchcastHidden()").count == 5,
            "The four hidden rows are gone from the General pane")
        precondition(hiddenRows(in: "Tinycast/Features/Notes/Settings/NotesSettingsView.swift") == 1)
        let calendar = source("Tinycast/Features/Calendar/Settings/CalendarSettingsView.swift")
        precondition(
            hiddenRows(in: "Tinycast/Features/Calendar/Settings/CalendarSettingsView.swift") == 5,
            "Five Menu Bar rows are gone from the Calendar pane")
        precondition(calendar.contains("\"Days to Show\""), "Days to Show stays: it sets the span for every surface")

        precondition(
            settings.contains("var showInMenuBar: Bool {\n        get { false }"),
            "The menu-bar icon is never inserted")
        precondition(
            settings.contains("var notesShowsInMenuBar: Bool {\n        get { false }"),
            "The Notes menu-bar item is never created")
        precondition(
            settings.contains("var calendarMenuBarDisplay: CalendarMenuBarDisplay {\n        get { .disabled }"),
            "The calendar menu-bar item is never inserted")
        for key in ["showInMenuBar", "notesShowsInMenuBar", "calendarMenuBarDisplay"] {
            precondition(!settings.contains("\n        \(key) ="), "AppSettings.\(key) ignores persisted values")
        }
        precondition(
            source("Tinycast/Features/Backup/Settings/RaycastImportSelection.swift")
                .contains(".filter { $0.option != .menuBarVisibility }"),
            "Raycast import offers no menu-bar icon checkbox")
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .about && $0.keywords.contains("Support") },
            "About still lists Support")
        print("Hidden features: Extensions, appearance, dragging, placement and menu-bar items are hidden")
    }

    static func hiddenRows(in path: String) -> Int {
        source(path).components(separatedBy: ".notchcastHidden()").count - 1
    }

    static func source(_ path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("Cannot read \(path)")
        }
        return text
    }
}
