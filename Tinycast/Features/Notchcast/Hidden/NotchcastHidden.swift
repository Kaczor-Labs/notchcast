// Hidden rather than removed, so upstream code still compiles and rebases; notchcast/docs/hidden.md.
enum NotchcastHidden {
    static let tabs: Set<SettingsTab> = [.extensions]
    /// English keys of the Settings rows the island makes meaningless; search drops them.
    static let rows: Set<String> = [
        "Appearance", "Follow the cursor across displays", "Drag to move the launcher",
        "Show in menu bar", "Show in Menu Bar", "Calendar in Menu Bar", "Show Upcoming Events",
        "Only show events with meetings", "Hide when there are no upcoming events",
        "Hide Current Event",
    ]

    static func hides(tab: SettingsTab, keywords: [String]) -> Bool {
        tabs.contains(tab) || !rows.isDisjoint(with: keywords)
    }
}
