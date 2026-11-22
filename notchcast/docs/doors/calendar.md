# Door: Calendar

`context.calendar` exposes stock Calendar's EventKit service to the Day add-on. `events()` returns the current snapshot as `NotchcastEvent` values, excluding declined events. `showSchedule()` opens My Schedule from Day's event rows. `NotchcastCalendar+Live.swift` connects these operations to `AppCore`. The default door returns an empty snapshot and does nothing for actions.

Turning on Day in the Island requests macOS calendar access when it is undetermined. The bridge reuses an existing grant and enables the event store only after access is granted. Day's Grant Access button also opens Calendars privacy settings if macOS has denied access. Settings restores and launch use previous consent without presenting a prompt. See [hidden.md](../hidden.md) for the Calendar surfaces.
