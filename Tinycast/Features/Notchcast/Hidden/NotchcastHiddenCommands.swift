/// Hidden whatever is stored; both ship empty, only a harness fills them. notchcast/docs/hidden.md.
@MainActor
enum NotchcastHiddenCommands {
    /// Gone from the launcher, and with it from hotkeys and deeplinks.
    static var commands: Set<CommandID> = []
    /// Read as off whatever `hiddenLauncherKinds` stores; a kind can only be forced off, never on.
    static var kinds: Set<AppEntry.Kind> = []
}
