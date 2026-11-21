// Hidden rather than removed, so upstream code still compiles and rebases; notchcast/docs/hidden.md.
enum NotchcastHidden {
    static let tabs: Set<SettingsTab> = [
        .extensions,
        .appleShortcuts,
        .iCloudSync,
        .systemSettings,
        .navigation,
        .quickActions,
        .commands,
    ]
    /// The app speaks English only; `AppSettings.pinLanguage()` writes this at every launch.
    static let language = "en"
    /// English keys of the rows hidden in each tab; search drops them there and nowhere else.
    static let rows: [SettingsTab: Set<String>] = [
        .general: [
            "Appearance", "Follow the cursor across displays", "Drag to move the launcher", "Language",
            "Show in menu bar",
        ],
        .notes: ["Show in Menu Bar"],
        .about: ["Support"],
        .calendar: [
            "Calendar in Menu Bar", "Show Upcoming Events", "Only show events with meetings",
            "Hide when there are no upcoming events", "Hide Current Event",
        ],
    ]

    static func hides(tab: SettingsTab, keywords: [String]) -> Bool {
        tabs.contains(tab) || rows[tab]?.isDisjoint(with: keywords) == false
    }
}
