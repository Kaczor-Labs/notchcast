import AppKit

extension NotchcastCalendar {
    @MainActor
    init(core: AppCore, activate: @escaping @MainActor () -> Void = { NSApp.activate() }) {
        var requestingAccess = false
        self.init(
            events: { [weak core] in
                (core?.calendarStore.events ?? []).filter { !$0.isDeclined }.map {
                    NotchcastEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
                }
            },
            showSchedule: { [weak core] in core?.calendarCoordinator.showSchedule() },
            needsAccess: { [weak core] in
                guard let core else { return false }
                return core.calendarStore.access != .granted
            },
            requestAccess: { [weak core] openSettingsIfDenied in
                guard let core, !requestingAccess else { return }
                let store = core.calendarStore
                let previousAccess = store.access
                store.refreshAccess()
                switch store.access {
                case .granted:
                    if previousAccess != .granted { store.start() }
                case .notDetermined:
                    requestingAccess = true
                    defer { requestingAccess = false }
                    activate()
                    _ = await Permissions.requestCalendarAccess()
                    store.refreshAccess()
                    if store.access == .granted { store.start() }
                case .denied:
                    if openSettingsIfDenied { Permissions.openCalendarSettings() }
                }
            })
    }
}
