import Foundation

/// A command's Hyper default, bound once when first enabled; never over a user's choice or a clash.
@MainActor
enum NotchcastHotKeyDefaults {
    static let seededKey = "seededHotKeys"

    /// `wanted` pairs entry ids with Carbon key codes; `free` says the binding clashes with nothing.
    static func seed(_ wanted: [(id: String, keyCode: Int)], includesShift: Bool, defaults: UserDefaults,
                     bound: (HotKeyAction) -> Bool, free: (HotKeyBinding, HotKeyAction) -> Bool,
                     bind: (HotKeyBinding, HotKeyAction) -> Void) {
        var seeded = Set(defaults.stringArray(forKey: seededKey) ?? [])
        let fresh = wanted.filter { !seeded.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let chord = KeyShortcut.carbonModifiers(from: KeyShortcut.hyperChord(includesShift: includesShift))
        for command in fresh {
            seeded.insert(command.id)
            let action = HotKeyAction.notchcastCommand(entryID: command.id)
            let binding = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: command.keyCode, carbonModifiers: chord))
            if !bound(action), free(binding, action) { bind(binding, action) }
        }
        defaults.set(seeded.sorted(), forKey: seededKey)
    }
}
