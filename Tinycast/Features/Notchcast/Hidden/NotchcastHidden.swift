// Hidden rather than removed, so upstream code still compiles and rebases; notchcast/docs/hidden.md.
enum NotchcastHidden {
    static let tabs: Set<SettingsTab> = [.extensions, .appleShortcuts, .iCloudSync]
    /// The app speaks English only; `AppSettings.pinLanguage()` writes this at every launch.
    static let language = "en"
    /// English keys of the General rows the island or the English-only build makes meaningless;
    /// search drops them.
    static let rows: Set<String> = [
        "Appearance", "Follow the cursor across displays", "Drag to move the launcher", "Language",
        "Show in menu bar", "Show in Menu Bar", "Calendar in Menu Bar", "Show Upcoming Events",
        "Only show events with meetings", "Hide when there are no upcoming events",
        "Hide Current Event",
    ]

    static func hides(tab: SettingsTab, keywords: [String]) -> Bool {
        tabs.contains(tab) || (tab == .general && !rows.isDisjoint(with: keywords))
    }
}
