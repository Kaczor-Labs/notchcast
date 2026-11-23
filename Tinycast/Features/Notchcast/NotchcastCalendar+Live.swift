extension NotchcastCalendar {
    @MainActor
    init(core: AppCore) {
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
                return !core.settings.calendarEnabled || core.calendarStore.access != .granted
            },
            requestAccess: { [weak core] openSettingsIfDenied in
                guard let core, !requestingAccess else { return }
                let store = core.calendarStore
                store.refreshAccess()
                switch store.access {
                case .granted:
                    break
                case .notDetermined:
                    requestingAccess = true
                    defer { requestingAccess = false }
                    guard await store.requestAccess() else { return }
                case .denied:
                    if openSettingsIfDenied { Permissions.openCalendarSettings() }
                    return
                }
                if !core.settings.calendarEnabled {
                    core.settings.calendarEnabled = true
                } else {
                    store.start()
                }
            })
    }
}
