// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/KeyShortcut.swift Tinycast/Features/HotKeys/Service/HotKeyManager.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift Tests/HotKeyDispatchFixtures.swift
import AppKit
import Carbon.HIToolbox

@main
@MainActor
struct NotchcastHotKeysTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        for includesShift in [false, true] { secureInputFollowsExtraActions(includesShift: includesShift) }
        print("\(checks) add-on hotkey checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    /// Hook H5: an add-on's secure-input equivalent lives and dies with its entry in `extraActions`.
    static func secureInputFollowsExtraActions(includesShift: Bool) {
        let domain = "tinycast.notchcast-hotkeys-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = HotKeyManager(defaults: defaults)
        let center = HotKeyCenter.current!
        var ran: [String] = []
        var palette = 0
        manager.onRunNotchcastCommand = { ran.append($0) }
        manager.onTogglePalette = { palette += 1 }
        let chord = KeyShortcut.hyperChord(includesShift: includesShift)
        let hyper = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: KeyShortcut.carbonModifiers(from: chord))
        let control = KeyShortcut(carbonKeyCode: kVK_ANSI_G, carbonModifiers: controlKey)
        let probe = HotKeyAction.notchcastCommand(entryID: "command:nc-probe")
        let equivalentID = "secureInputEquivalent." + probe.defaultsKey
        let paletteID = HotKeyAction.togglePalette.defaultsKey
        let label = includesShift ? "shift" : "plain"

        manager.extraActions = [probe]
        manager.setBinding(.combo(hyper), for: probe)
        manager.setBinding(.combo(control), for: .togglePalette)
        manager.setSecureInputEquivalents(includesShift: includesShift)
        check("\(label): the enabled add-on gets an equivalent on ⌃G", center.entries[equivalentID]?.shortcut == control)
        check("\(label): the equivalent displaces the stock ⌃G", center.entries[paletteID] == nil)
        center.entries[equivalentID]?.onKeyDown(CGEventFlags.maskControl.rawValue | 0x2000)
        center.entries[equivalentID]?.onKeyUp?()
        check("\(label): right Control runs the add-on command", ran == ["command:nc-probe"] && palette == 0)

        manager.extraActions = []
        check("\(label): disabling the add-on drops its equivalent", center.entries[equivalentID] == nil)
        check("\(label): disabling the add-on gives ⌃G back", center.entries[paletteID]?.shortcut == control)
        check("\(label): nothing else stays registered for the add-on", center.entries[probe.defaultsKey] == nil)

        manager.extraActions = [probe]
        check("\(label): re-enabling rebuilds the equivalent", center.entries[equivalentID]?.shortcut == control)
        check("\(label): re-enabling displaces ⌃G again", center.entries[paletteID] == nil)
        manager.setSecureInputEquivalents(includesShift: nil)
    }
}
