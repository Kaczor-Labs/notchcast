// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHiddenCommands.swift
import AppKit
import Foundation

enum AppEntry { enum Kind { case systemSettings } }
enum HotKeyAction { case command(CommandID) }
enum Quicklink { static let sfSymbol = "link" }

@main
@MainActor
struct HiddenFeaturesTest {
    static func main() {
        let visible = SettingsSection.allCases.flatMap(\.tabs)
        let calendarChecks = [
            ("Calendar is absent from the sidebar", !visible.contains(.calendar)),
            ("settings/calendar is rejected", SettingsTab(slug: "calendar") == nil),
            ("Calendar is absent from Settings search", !SettingsSearchCatalog.entries.contains { $0.tab == .calendar }),
            ("Calendars permission is absent from Settings search",
             !SettingsSearchCatalog.entries.contains { $0.anchor == .permissionsCalendars }),
        ]
        let failures = calendarChecks.filter { !$0.1 }
        for (message, _) in failures { print("FAIL: \(message)") }
        if !failures.isEmpty { exit(1) }
        let calendarCommands: [CommandID] = [
            .joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar,
        ]
        for command in calendarCommands {
            precondition(NotchcastHiddenCommands.commands.contains(command), "Hidden Calendar command: \(command)")
        }

        for tab in [
            SettingsTab.extensions, .appleShortcuts, .iCloudSync, .systemSettings, .navigation, .quickActions,
            .commands, .notes, .ai, .fallbacks,
        ] {
            precondition(!visible.contains(tab), "Hidden tab stays out of the sidebar: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == nil, "settings/\(tab.slug) opens nothing")
            precondition(!SettingsSearchCatalog.entries.contains { $0.tab == tab }, "Search omits \(tab.slug)")
        }
        for tab in [SettingsTab.backup, .about, .systemActions] {
            precondition(visible.contains(tab), "Stock tab stays visible: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == tab, "settings/\(tab.slug) still opens")
            precondition(SettingsSearchCatalog.entries.contains { $0.tab == tab })
        }

        let hiddenRows: [(SettingsTab, [String])] = [
            (.general, [
                "Appearance", "Follow the cursor across displays", "Drag to move the launcher", "Language",
                "Show in menu bar",
            ]),
            (.notes, ["Show in Menu Bar"]),
            (.about, ["Support"]),
        ]
        for (tab, titles) in hiddenRows {
            for title in titles {
                precondition(
                    !SettingsSearchCatalog.entries.contains { $0.tab == tab && $0.keywords.contains(title) },
                    "Search omits the hidden \(tab.slug) row: \(title)")
            }
        }
        precondition(
            NotchcastHidden.hides(tab: .notes, keywords: ["Show in Menu Bar"])
                && !NotchcastHidden.hides(tab: .general, keywords: ["Show in Menu Bar"]),
            "A row is hidden only in the tab that lists it")
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .dictation && $0.keywords.contains("Language") },
            "Dictation's own Language row is a separate setting and stays searchable")
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .dictation && $0.keywords.contains("AI providers") },
            "With the AI tab hidden, Dictation's Cleanup holds the AI providers row")
        for title in ["Show animations", "Interface size", "Window mode"] {
            precondition(
                SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) },
                "Search keeps the stock row: \(title)")
        }
        for title in ["Enable Quick Actions", "Add Quick Action"] {
            precondition(!SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) }, "Search omits \(title)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .about && $0.keywords.contains("Links") },
            "About keeps its Links")
        print("Hidden features: hidden tabs, rows and Calendar commands stay hidden")
    }
}
