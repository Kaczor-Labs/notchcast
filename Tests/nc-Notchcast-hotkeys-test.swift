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
        shippedCommandsTakeHotKeys()
        hiddenFeatureBindingsStayUnregistered()
        hiddenChordsOwnNothing()
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

    /// Two shipped add-on commands take a chord like a stock command: stored, registered, fired.
    static func shippedCommandsTakeHotKeys() {
        let domain = "tinycast.notchcast-hotkeys-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = HotKeyManager(defaults: defaults)
        let center = HotKeyCenter.current!
        var ran: [String] = []
        manager.onRunNotchcastCommand = { ran.append($0) }
        let commands = [("command:nc-generate-password", kVK_ANSI_1), ("command:nc-screenshot-area", kVK_ANSI_2)]
        let actions = commands.map { HotKeyAction.notchcastCommand(entryID: $0.0) }
        manager.extraActions = actions
        for ((id, key), action) in zip(commands, actions) {
            let chord = KeyShortcut(carbonKeyCode: key, carbonModifiers: controlKey | optionKey)
            manager.setBinding(.combo(chord), for: action)
            check("\(id): its chord is registered", center.entries[action.defaultsKey]?.shortcut == chord)
            center.entries[action.defaultsKey]?.onKeyDown(0)
            check("\(id): pressing its chord runs it", ran.last == id)
            check("\(id): stored under its stock-shaped key", defaults.string(forKey: "hotkey." + id) != nil)
        }
        check("each chord ran exactly its own command", ran == commands.map(\.0))
        let relaunched = HotKeyManager(defaults: defaults)
        relaunched.extraActions = actions
        let relaunchedCenter = HotKeyCenter.current!
        check("both chords are registered again after a relaunch",
              relaunchedCenter !== center && actions.allSatisfy { relaunchedCenter.entries[$0.defaultsKey] != nil })
    }

    /// A refused stored chord stays unregistered; the `hidden-hotkeys` app proof pins AppCore's real gate.
    static func hiddenFeatureBindingsStayUnregistered() {
        let domain = "tinycast.notchcast-hotkeys-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let quicklink = UUID()
        let quickAction = UUID()
        let hidden: [HotKeyAction] = [
            .appleShortcut(id: UUID()), .extensionCommand(entryID: "ext.cmd"), .quickAction(id: quickAction),
        ]
        let manager = HotKeyManager(defaults: defaults)
        let keys = [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_6, kVK_ANSI_5]
        for (action, key) in zip(hidden + [.quicklink(id: quicklink)], keys) {
            manager.setBinding(.combo(KeyShortcut(carbonKeyCode: key, carbonModifiers: controlKey)), for: action)
        }
        let relaunched = HotKeyManager(defaults: defaults)
        relaunched.allowsAction = { !hidden.contains($0) }
        relaunched.start(
            customCommandIDs: [], quicklinkIDs: [quicklink], windowLayoutIDs: [],
            windowRoomIDs: [], customWindowSizeIDs: [], quickActionIDs: [quickAction])
        let entries = HotKeyCenter.current!.entries
        check("a stored quicklink chord registers after a relaunch",
              entries[HotKeyAction.quicklink(id: quicklink).defaultsKey] != nil)
        for action in hidden {
            check("\(action.defaultsKey): its chord stays unregistered", entries[action.defaultsKey] == nil)
        }
    }
    /// #1285: a chord a hidden feature stored before the hide neither blocks the recorder nor takes a tap.
    static func hiddenChordsOwnNothing() {
        let domain = "tinycast.notchcast-hotkeys-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let quicklinkID = UUID()
        let quicklink = HotKeyAction.quicklink(id: quicklinkID)
        let hidden = HotKeyAction.appleShortcut(id: UUID())
        let combo = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_7, carbonModifiers: controlKey))
        let quicklinkCombo = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_8, carbonModifiers: controlKey))
        let manager = HotKeyManager(defaults: defaults)
        manager.setBinding(combo, for: hidden)
        manager.setBinding(quicklinkCombo, for: quicklink)
        let relaunched = HotKeyManager(defaults: defaults)
        relaunched.allowsAction = { $0 != hidden }
        relaunched.start(
            customCommandIDs: [], quicklinkIDs: [quicklinkID], windowLayoutIDs: [],
            windowRoomIDs: [], customWindowSizeIDs: [], quickActionIDs: [])
        check("unhidden, the stored chord names its owner",
              relaunched.conflictOwner(of: combo, excluding: .togglePalette) != nil)
        relaunched.isHidden = { $0 == hidden }
        check("a hidden feature's stored chord blocks no recording",
              relaunched.conflictOwner(of: combo, excluding: .togglePalette) == nil)
        check("a visible stored chord still names its owner",
              relaunched.conflictOwner(of: quicklinkCombo, excluding: .togglePalette) != nil)
        relaunched.setBinding(combo, for: .togglePalette)
        check("the freed chord registers for the new owner",
              HotKeyCenter.current!.entries[HotKeyAction.togglePalette.defaultsKey]?.shortcut == combo.shortcut)
    }
}
