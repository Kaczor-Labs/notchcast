# Door: Calendar

**Calendar** is stock Calendar behind `context.calendar` (`NotchcastCalendar`, `Core/Service/NotchcastCalendar.swift`): `events()` returns what the Calendar feature holds now as `NotchcastEvent` values (declined ones left out; empty while Calendar is off or has no access) and `showSchedule()` opens its My Schedule screen. `NotchcastCalendar+Live.swift` builds both closures from `AppCore`, so no add-on names a Calendar type; a harness passes its own, and the default is an empty calendar. The Day add-on (`Day/`, [day-page.md](../day-page.md)) is its user.
