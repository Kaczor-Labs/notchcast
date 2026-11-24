// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHiddenCommands.swift
// notchcast-sources: Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Calendar/Service/CalendarStore.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift Tinycast/Platform/NotificationToken.swift
import AppKit
import Foundation

enum AppEntry { enum Kind { case systemSettings } }
enum HotKeyAction { case command(CommandID) }
enum Quicklink { static let sfSymbol = "link" }

@MainActor
enum Permissions {
    static var access: CalendarAccess = .granted
    private(set) static var reads = 0

    static func calendarAccess() -> CalendarAccess {
        reads += 1
        return access
    }

    static func requestCalendarAccess() async -> Bool {
        preconditionFailure("Starting the shared store must never prompt")
    }
}

@main
@MainActor
struct HiddenFeaturesTest {
    static func main() {
        checkCalendarStoreStartsWithCalendarOff()

        let visible = SettingsSection.allCases.flatMap(\.tabs)
        let calendarChecks = [
            ("Calendar is absent from the sidebar", !visible.contains(.calendar)),
            ("settings/calendar is rejected", SettingsTab(slug: "calendar") == nil),
            ("Calendar is absent from Settings search", !SettingsSearchCatalog.entries.contains { $0.tab == .calendar }),
            ("Calendars permission is absent from Settings search",
             !SettingsSearchCatalog.entries.contains { $0.anchor == .permissionsCalendars }),
        ]
        let dictationChecks = [
            ("Dictation is absent from Features", !visible.contains(.dictation)),
            ("settings/dictation is rejected", SettingsTab(slug: "dictation") == nil),
            ("the stock Dictation tab is absent from Settings search",
             !SettingsSearchCatalog.entries.contains { $0.tab == .dictation }),
            ("direct navigation to the stock Dictation tab is refused", NotchcastHidden.tabs.contains(.dictation)),
            ("Notchcast › Dictation shows with no add-on", visible.contains(.notchcast(.dictation))),
            ("Notchcast › Dictation sits after Keyboard & Mouse",
             NotchcastPane.allCases.firstIndex(of: .dictation)
                == NotchcastPane.allCases.firstIndex(of: .keyboardMouse).map { $0 + 1 }),
            ("settings/notchcast-dictation opens the new tab",
             SettingsTab(slug: "notchcast-dictation") == .notchcast(.dictation)),
            ("the Dictation History chord stays live with its owner tab hidden",
             NotchcastHidden.liveCommandTabs == [.dictation]),
            ("a tab whose commands live on is still a hidden tab",
             NotchcastHidden.liveCommandTabs.isSubset(of: NotchcastHidden.tabs)),
        ]
        let failures = (calendarChecks + dictationChecks).filter { !$0.1 }
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
            SettingsSearchCatalog.entries.contains {
                $0.tab == .notchcast(.dictation) && $0.keywords.contains("AI providers")
            },
            "With the AI tab hidden, Notchcast › Dictation's Cleanup holds the AI providers row")
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
        print("Hidden features: tabs, rows and Calendar commands stay hidden. The granted Calendar store still starts.")
    }

    private static func checkCalendarStoreStartsWithCalendarOff() {
        let store = CalendarStore()
        let readsBeforeStart = Permissions.reads
        NotchcastHidden.applyDisabledCalendarStore(start: store.start, stop: {
            preconditionFailure("Disabling hidden Calendar must keep the shared event store running")
        })
        Permissions.access = .denied
        precondition(store.access == .granted && Permissions.reads == readsBeforeStart + 1,
                     "A store starting with Calendar off must refresh and accept an existing grant")
    }
}
