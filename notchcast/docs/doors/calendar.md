# Door: Calendar

`context.calendar` exposes the shared Calendar service to add-ons. `events()` returns the current event snapshot as `NotchcastEvent` values, excluding declined events. `showSchedule()` opens My Schedule.

`needsAccess()` reads whether macOS full calendar access is missing. `requestAccess(openSettingsIfDenied:)` brings the main app forward before asking macOS for an undetermined grant, and can open Privacy & Security › Calendars when access has already been denied. A newly granted permission starts the event store. The upstream Calendar feature switch keeps its own consent flow.

`NotchcastCalendar+Live.swift` wires the door to `AppCore`. The default door returns an empty snapshot, reports no access requirement and does nothing for actions.
