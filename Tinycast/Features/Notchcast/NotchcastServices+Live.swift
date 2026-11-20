extension NotchcastServices {
    /// The live doors, one line each (merge=union); each door's own `+Live` file reaches the app.
    init(core: AppCore) {
        self.init()
        clipboard = NotchcastClipboardMutation(core: core)
        surfaces = NotchcastSurfaces(core: core)
        settingsBackup = NotchcastSettingsBackupBridge(core: core)
        calendar = NotchcastCalendar(core: core)
    }
}
