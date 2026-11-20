// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
import AppKit
import Foundation

@main
struct HiddenFeaturesTest {
    static func main() {
        let visible = SettingsSection.allCases.flatMap(\.tabs)
        for tab in [
            SettingsTab.extensions, .appleShortcuts, .iCloudSync, .systemSettings, .navigation, .quickActions, .commands,
            .notes,
        ] {
            precondition(!visible.contains(tab), "Hidden tab stays out of the sidebar: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == nil, "settings/\(tab.slug) opens nothing")
            precondition(!SettingsSearchCatalog.entries.contains { $0.tab == tab }, "Search omits \(tab.slug)")
        }
        for tab in [SettingsTab.backup, .about, .fallbacks, .systemActions, .calendar] {
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
            (.calendar, [
                "Calendar in Menu Bar", "Show Upcoming Events", "Only show events with meetings",
                "Hide when there are no upcoming events", "Hide Current Event",
                "Upcoming meetings in launcher",
                "Auto Join Meetings",
                "Only join known meeting services",
                "Confirm before joining",
                "Camera Preview",
                "Calendar commands",
            ]),
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
        for title in ["Show animations", "Interface size", "Window mode", "Days to Show"] {
            precondition(
                SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) },
                "Search keeps the stock row: \(title)")
        }
        for title in ["Enable Quick Actions", "Add Quick Action"] {
            precondition(!SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) }, "Search omits \(title)")
        }
        for title in [
            "Join meetings from Tinycast", "Show the meeting card", "Open Meeting Links In", "Days to Show", "Calendars",
        ] {
            precondition(
                SettingsSearchCatalog.entries.contains { $0.tab == .calendar && $0.keywords.contains(title) },
                "Calendar keeps its row: \(title)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .about && $0.keywords.contains("Links") },
            "About keeps its Links")
        print("Hidden features: the hidden tabs and rows stay out of Settings")
    }
}
