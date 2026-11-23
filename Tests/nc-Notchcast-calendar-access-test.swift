// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastCalendar.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastCalendar+Live.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift
import Foundation

@MainActor
struct NotchcastContext {
    var services: Services

    struct Services {
        var calendar: NotchcastCalendar
    }
}

@MainActor
final class AppCore {
    let calendarStore = CalendarStore()
    let calendarCoordinator = CalendarCoordinator()
    let settings = Settings()
}

@MainActor
final class Settings {
    var calendarEnabled = true
}

@MainActor
final class CalendarCoordinator {
    func showSchedule() {}
}

@MainActor
final class CalendarStore {
    var access = Permissions.access
    let events: [Event] = []
    private(set) var starts = 0

    struct Event {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let isDeclined: Bool
    }

    func refreshAccess() { access = Permissions.access }
    func start() { starts += 1 }
}

@MainActor
enum Permissions {
    static var access: CalendarAccess = .notDetermined
    static var request: (() async -> Void)?
    static var settingsOpened = 0

    static func requestCalendarAccess() async -> Bool {
        await request?()
        return access == .granted
    }

    static func openCalendarSettings() { settingsOpened += 1 }
}

@main
@MainActor
struct NotchcastCalendarAccessTest {
    static func main() async {
        var activations = 0
        let core = AppCore()
        let calendar = NotchcastCalendar(core: core, activate: { activations += 1 })
        var prompts = 0
        Permissions.request = {
            prompts += 1
            precondition(activations == prompts, "Activate the main app before asking macOS")
            if prompts == 1 {
                await calendar.requestAccess(true)
                Permissions.access = .denied
            } else {
                Permissions.access = .granted
            }
        }
        core.settings.calendarEnabled = false

        precondition(calendar.needsAccess(), "Undetermined access needs a grant")
        precondition(prompts == 0, "Creating the door and reading status must never prompt")
        await calendar.requestAccess(true)
        precondition(prompts == 1, "Concurrent requests must share one prompt")
        precondition(calendar.needsAccess(), "A refusal leaves the grant missing")
        precondition(Permissions.settingsOpened == 0, "Show Settings only on a subsequent request")
        precondition(core.calendarStore.starts == 0, "No event reads before consent")
        precondition(!core.settings.calendarEnabled, "A refused request must leave Calendar off")

        await calendar.requestAccess(false)
        precondition(Permissions.settingsOpened == 0, "Opening System Settings is opt-in")
        await calendar.requestAccess(true)
        precondition(Permissions.settingsOpened == 1, "Existing denial opens Calendars privacy settings")
        precondition(prompts == 1, "Existing denial cannot prompt again")

        Permissions.access = .granted
        await calendar.requestAccess(true)
        precondition(!calendar.needsAccess(), "A fresh system grant must clear the access requirement")
        precondition(core.calendarStore.starts == 1, "Use a grant made in System Settings")

        await calendar.requestAccess(true)
        precondition(!calendar.needsAccess(), "Calendar off with full access still has a grant")
        precondition(!core.settings.calendarEnabled, "The Day action must leave Calendar off")
        core.settings.calendarEnabled = true
        precondition(!calendar.needsAccess(), "Calendar on with full access has a grant")
        await calendar.requestAccess(true)
        precondition(prompts == 1 && core.calendarStore.starts == 1, "An existing grant requires no work")

        Permissions.access = .notDetermined
        core.settings.calendarEnabled = false
        await calendar.requestAccess(true)
        precondition(prompts == 2 && !calendar.needsAccess(), "A new macOS grant clears the access requirement")
        precondition(core.calendarStore.starts == 2, "A new macOS grant starts the event store")
        precondition(!core.settings.calendarEnabled, "A successful request must leave Calendar off")

        print("Calendar access: prompt, denial, Settings grant and existing grants")
    }
}
