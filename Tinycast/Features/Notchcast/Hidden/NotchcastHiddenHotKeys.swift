/// Chords a hidden feature stored before the hide: no screen is left to clear them. hidden.md.
@MainActor
enum NotchcastHiddenHotKeys {
    static func hides(_ action: HotKeyAction) -> Bool {
        switch action {
        case .appleShortcut: NotchcastHidden.tabs.contains(.appleShortcuts)
        case .extensionCommand: NotchcastHidden.tabs.contains(.extensions)
        case .quickAction: NotchcastHidden.tabs.contains(.quickActions)
        case .customCommand: NotchcastHidden.tabs.contains(.commands)
        case .settingsPane: NotchcastHiddenCommands.kinds.contains(.systemSettings)
        case .command(let id):
            NotchcastHiddenCommands.commands.contains(id) || id.owner.map(NotchcastHidden.tabs.contains) == true
        default: false
        }
    }
}
