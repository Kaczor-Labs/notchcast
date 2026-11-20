/// Hidden whatever is stored; harnesses may refill them. notchcast/docs/hidden.md.
@MainActor
enum NotchcastHiddenCommands {
    /// Gone from the launcher, and with it from hotkeys and deeplinks.
    static var commands: Set<CommandID> = Set([
        "command:support",
        "command:create-custom-command",
        "command:search-custom-commands",
        "command:run-shell-command",
        "command:join-next-meeting",
        "command:my-schedule",
        "command:create-event",
        "command:copy-meeting-link",
        "command:open-in-calendar",
        "command:show-notes",
        "command:create-note",
        "command:search-notes",
    ].compactMap(CommandID.init(rawValue:)))
    /// Read as off whatever `hiddenLauncherKinds` stores; a kind can only be forced off, never on.
    static var kinds: Set<AppEntry.Kind> = [
        .systemSettings,
    ]
}
