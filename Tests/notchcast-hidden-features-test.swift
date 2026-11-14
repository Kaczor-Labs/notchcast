// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
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
        print("Hidden features: only Extensions is hidden")
    }
}
