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
// notchcast-reads: Tinycast/Features/Backup/Model/SettingsBackup.swift
// notchcast-reads: Tinycast/Features/Settings/SettingsFileSchema.swift
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

        let titles = ["Appearance", "Follow the cursor across displays", "Drag to move the launcher", "Language"]
        precondition(NotchcastHidden.rows == Set(titles))
        for title in titles {
            precondition(
                !SettingsSearchCatalog.entries.contains { $0.tab == .general && $0.keywords.contains(title) },
                "Search omits the hidden row: \(title)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .dictation && $0.keywords.contains("Language") },
            "Dictation's own Language row is a separate setting and stays searchable")
        for title in ["Show animations", "Interface size", "Window mode"] {
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

        precondition(NotchcastHidden.language == "en", "The app is pinned to English")
        let pin = settings.components(separatedBy: "static func pinLanguage() {")[1].components(separatedBy: "\n    }")[0]
        precondition(
            pin.contains("set([NotchcastHidden.language], forKey: Key.language.rawValue)"),
            "pinLanguage writes the fork constant")
        precondition(!pin.contains("storedLanguage"), "pinLanguage never reads back a stored language")
        precondition(
            settings.contains("var language: AppLanguage {\n        get { .english }\n        set { }"),
            "An imported language is dropped in-session, so no relaunch is offered")
        for (path, channel) in [
            ("Tinycast/Features/Backup/Model/SettingsBackup.swift", "settings.language = language"),
            ("Tinycast/Features/Settings/SettingsFileSchema.swift", "bind(settings, \\.language)"),
        ] {
            precondition(source(path).contains(channel), "Import channel still routes through AppSettings.language: \(path)")
        }
        precondition(
            SettingsSearchCatalog.entries.contains { $0.tab == .about && $0.keywords.contains("Support") },
            "About still lists Support")
        print("Hidden features: Extensions, appearance, dragging, placement and language are hidden")
    }

    static func source(_ path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("Cannot read \(path)")
        }
        return text
    }
}
