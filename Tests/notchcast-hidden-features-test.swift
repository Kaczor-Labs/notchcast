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
        for tab in [SettingsTab.extensions, .appleShortcuts, .iCloudSync] {
            precondition(!visible.contains(tab), "Hidden tab stays out of the sidebar: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == nil, "settings/\(tab.slug) opens nothing")
            precondition(!SettingsSearchCatalog.entries.contains { $0.tab == tab }, "Search omits \(tab.slug)")
        }
        for tab in [SettingsTab.backup, .about, .fallbacks] {
            precondition(visible.contains(tab), "Stock tab stays visible: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == tab, "settings/\(tab.slug) still opens")
            precondition(SettingsSearchCatalog.entries.contains { $0.tab == tab })
        }

        let hiddenRows = [
            "Appearance", "Follow the cursor across displays", "Drag to move the launcher", "Language",
            "Show in menu bar", "Show in Menu Bar", "Calendar in Menu Bar", "Show Upcoming Events",
            "Only show events with meetings", "Hide when there are no upcoming events", "Hide Current Event",
        ]
        for title in hiddenRows {
            precondition(
                !SettingsSearchCatalog.entries.contains { $0.tab == .general && $0.keywords.contains(title) },
                "Search omits the hidden row: \(title)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .dictation && $0.keywords.contains("Language") },
            "Dictation's own Language row is a separate setting and stays searchable")
        for title in ["Show animations", "Interface size", "Window mode", "Days to Show"] {
            precondition(
                SettingsSearchCatalog.entries.contains { $0.keywords.contains(title) },
                "Search keeps the stock row: \(title)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .about && $0.keywords.contains("Support") },
            "About still lists Support")
        print("Hidden features: Extensions, Apple Shortcuts and iCloud Sync tabs and the hidden rows stay out of Settings")
    }
}
