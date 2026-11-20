extension NotchcastCalendar {
    @MainActor
    init(core: AppCore) {
        self.init(
            events: { [weak core] in
                (core?.calendarStore.events ?? []).filter { !$0.isDeclined }.map {
                    NotchcastEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
                }
            },
            showSchedule: { [weak core] in core?.calendarCoordinator.showSchedule() })
    }
}
