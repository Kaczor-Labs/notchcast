import Foundation

/// Chords a hidden feature stored before the hide: no screen is left to clear them. hidden.md.
@MainActor
enum NotchcastHiddenHotKeys {
    private static let hiddenBindingKeys = "notchcast.hiddenHotKeyBindingKeys"

    static func reconcileBindings(_ hotKeys: HotKeyManager, _ actions: [HotKeyAction], _ defaults: UserDefaults) {
        let remembered = Set(defaults.stringArray(forKey: hiddenBindingKeys) ?? [])
        var retained = Set<String>()
        var returning: [HotKeyAction] = []
        var live: [HotKeyAction] = []
        for action in actions {
            let key = action.defaultsKey
            if hotKeys.isHidden?(action) == true {
                if defaults.string(forKey: key) != nil { retained.insert(key) }
                continue
            }
            guard hotKeys.binding(for: action) != nil else { continue }
            if remembered.contains(key) {
                retained.insert(key)
                returning.append(action)
            } else {
                live.append(action)
            }
        }
        // Add-on bindings can load later, so keep tracking a returned chord until it is rewritten.
        if retained != remembered { defaults.set(retained.sorted(), forKey: hiddenBindingKeys) }
        for action in returning {
            guard let binding = hotKeys.binding(for: action),
                hotKeys.conflictOwner(of: binding, excluding: action, among: live) != nil
            else { continue }
            hotKeys.setBinding(nil, for: action)
        }
    }

    static func forgetHiddenBinding(_ action: HotKeyAction, _ defaults: UserDefaults) {
        guard var keys = defaults.stringArray(forKey: hiddenBindingKeys),
            let index = keys.firstIndex(of: action.defaultsKey)
        else { return }
        keys.remove(at: index)
        if keys.isEmpty {
            defaults.removeObject(forKey: hiddenBindingKeys)
        } else {
            defaults.set(keys, forKey: hiddenBindingKeys)
        }
    }

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
