// notchcast-sources: Tinycast/Features/Launcher/Service/VisibilityStore.swift Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/Launcher/Model/CommandCatalog.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift
import Foundation

// Stands in for AppIndex's entry; CommandCatalog and VisibilityStore read only these members.
struct AppEntry {
    enum Kind: String { case application, systemSettings, systemAction, command, quickAction }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    var settingsOwner: SettingsTab?
    var subtitle: String?
    var alternateTitles: [String] = []
    var preferenceKey: String { bundleID ?? id }
}

/// #1066: a typed web address earns its Open in Browser row whatever the Commands category says.
@main
@MainActor
enum NotchcastWebAddressTests {
    static func main() {
        let suite = "notchcast-web-address-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("no scratch suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VisibilityStore(defaults: defaults)
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures += 1; print("FAIL \(name)") }
        }
        // LauncherScreen leads with this row exactly when both of these hold.
        func row(_ query: String) -> AppEntry? {
            CommandCatalog.openInBrowser(for: query).flatMap { store.isVisible($0) ? $0 : nil }
        }
        let shell = CommandCatalog.makeEntry(.runShellCommand)
        check("Commands on offers the row", row("x.com") != nil)
        check("Commands on lists Run Shell Command", store.isVisible(shell))
        store.setKindEnabled(false, for: .command)
        check("Commands off still offers the row", row("x.com")?.id == CommandID.openInBrowser.rawValue)
        check("the row carries the address it opens", row("x.com")?.url.absoluteString == "https://x.com")
        check("Commands off offers no row for plain text", row("notes") == nil)
        check("Commands off hides Run Shell Command", !store.isVisible(shell))
        check("Commands off hides any other unowned command", !store.isVisible(CommandCatalog.makeEntry(.quit)))
        check("the fix leaves the stored switch off", defaults.stringArray(forKey: "hiddenLauncherKinds") == ["command"])
        store.setItemVisible(false, forKey: CommandID.openInBrowser.rawValue)
        check("the row's own Hide removes it", row("x.com") == nil)
        store.setKindEnabled(true, for: .command)
        check("its own Hide holds with Commands on", row("x.com") == nil)
        if failures > 0 { print("FAILED \(failures)/10"); exit(1) }
        print("PASSED")
    }
}
