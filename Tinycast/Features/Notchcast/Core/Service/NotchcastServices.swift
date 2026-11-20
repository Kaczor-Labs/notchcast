/// Every door from the app to an add-on, one line each with its inert default (merge=union).
@MainActor
struct NotchcastServices {
    var clipboard = NotchcastClipboardMutation.none
    var surfaces = NotchcastSurfaces()
    var settingsBackup: any NotchcastSettingsBackup = NotchcastNoSettingsBackup()
    var calendar = NotchcastCalendar()
}
