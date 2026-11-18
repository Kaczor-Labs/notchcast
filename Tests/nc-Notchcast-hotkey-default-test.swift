// notchcast-sources: Tinycast/Features/Notchcast/NotchcastHotKeyDefaults.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCommand.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Snippets/Model/Snippet.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/Quicklink.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
// notchcast-sources: Tinycast/DesignSystem/IconTint.swift
import Carbon.HIToolbox
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Notchcast-hotkey-default-test: \(message)") }
}

/// A command's Hyper default is bound once, never over the user's own choice or another binding.
@main
struct HotKeyDefaultTest {
    @MainActor
    static func main() {
        let suite = "nc-hotkey-default-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "command:nc-spotify-expand-player"
        var bindings: [HotKeyAction: HotKeyBinding] = [:]
        var taken: Set<HotKeyBinding> = []
        func seed(_ shift: Bool = true) {
            NotchcastHotKeyDefaults.seed([(id, kVK_ANSI_S)], includesShift: shift, defaults: defaults,
                bound: { bindings[$0] != nil }, free: { binding, _ in !taken.contains(binding) },
                bind: { bindings[$1] = $0 })
        }
        let action = HotKeyAction.notchcastCommand(entryID: id)
        let hyper = KeyShortcut.carbonModifiers(from: KeyShortcut.hyperChord(includesShift: true))
        let wanted = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_S, carbonModifiers: hyper))

        taken = [wanted]
        seed()
        check(bindings.isEmpty, "a clash leaves the command unbound")
        taken = []
        seed()
        check(bindings.isEmpty, "and the default is spent, so freeing the chord later binds nothing")

        defaults.removeObject(forKey: NotchcastHotKeyDefaults.seededKey)
        seed()
        check(bindings[action] == wanted, "first enable binds Hyper+S")
        bindings[action] = nil
        seed()
        check(bindings[action] == nil, "a user who clears it keeps it cleared")

        defaults.removeObject(forKey: NotchcastHotKeyDefaults.seededKey)
        let own = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_P, carbonModifiers: hyper))
        bindings[action] = own
        seed()
        check(bindings[action] == own, "a binding already chosen wins")

        defaults.removeObject(forKey: NotchcastHotKeyDefaults.seededKey)
        bindings = [:]
        seed(false)
        let threeKey = KeyShortcut.carbonModifiers(from: KeyShortcut.hyperChord(includesShift: false))
        check(bindings[action] == .combo(KeyShortcut(carbonKeyCode: kVK_ANSI_S, carbonModifiers: threeKey)),
              "Hyper without Shift binds the three-key chord")
        print("Notchcast hotkey default: bound once, never over a choice or a clash")
    }
}
