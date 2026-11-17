// notchcast-sources: Tinycast/Features/Launcher/Service/VisibilityStore.swift Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift
import Foundation

// Stands in for AppIndex's entry; VisibilityStore reads only these members.
struct AppEntry {
    enum Kind: String { case application, systemSettings, command, systemAction }
    let kind: Kind
    let settingsOwner: SettingsTab?
    let preferenceKey: String
}

// CommandCatalog's owner table pulls the whole launcher in; a stock command here has no owner.
extension CommandID { var owner: SettingsTab? { nil } }

/// An add-on command answers to its own switch, never to the stock Commands category.
@main
@MainActor
enum NotchcastVisibilityTests {
    static func main() {
        let suite = "notchcast-visibility-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("no scratch suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VisibilityStore(defaults: defaults)
        let action = HotKeyAction.notchcastCommand(entryID: "command:nc-sample")
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures += 1; print("FAIL \(name)") }
        }
        let entry = AppEntry(kind: .command, settingsOwner: .notchcast(.capture), preferenceKey: "command:nc-sample")
        check("Commands on allows an add-on command's hotkey", store.allowsHotKey(action))
        check("Commands on lists an add-on command", store.isVisible(entry))
        store.setKindEnabled(false, for: .command)
        check("Commands off still allows an add-on command's hotkey", store.allowsHotKey(action))
        check("Commands off still lists an add-on command", store.isVisible(entry))
        if failures > 0 { print("FAILED \(failures)/4"); exit(1) }
        print("PASSED")
    }
}
