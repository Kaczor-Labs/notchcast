// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/CustomQuickAction.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/Quicklink.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift
// notchcast-sources: Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCommand.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/Room.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Notchcast/NumberKeys/*.swift Tinycast/Features/Notchcast/NumberKeys/Model/*.swift
import CoreGraphics
import Foundation

/// The add-on through the real controller: ⌘<digit> reaches the module only while its switch is on.
@main
enum NumberKeysWiringTest {
    static func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func main() {
        let suite = "nc-numberkeys-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0x7E57, isTrusted: { true }) { _ in
            preconditionFailure("Number Keys must never start an event tap")
        }
        let controller = NotchcastController(
            addons: [NumberKeysAddon.self], defaults: defaults, hub: hub, presenter: IslandPresenter())
        let rows = [1, 2, 4, 5, 6, 8, 9, 11, 12, 14]
        controller.start()
        precondition(NumberKeysAddon.switchID == "launcherNumberKeys", "the v1 raw value is kept verbatim")
        precondition(!controller.preferences.isOn("launcherNumberKeys"), "off by default")
        for digit in 1...10 {
            precondition(controller.launcherRow(digit: digit, query: "sa", entryRows: rows) == nil, "off: stock slot")
        }

        controller.preferences.set("launcherNumberKeys", on: true)
        drain()
        for digit in 1...9 {
            precondition(controller.launcherRow(digit: digit, query: "sa", entryRows: rows) == rows[digit - 1])
        }
        precondition(controller.launcherRow(digit: 10, query: "sa", entryRows: rows) == nil, "⌘0 stays a favourite")
        precondition(controller.launcherRow(digit: 4, query: "sa", entryRows: [3, 7]) == nil, "past the rows")
        precondition(controller.launcherRow(digit: 1, query: " ", entryRows: rows) == nil, "no query: favourites")
        precondition(hub.subscriberCount == 0, "no event tap")

        controller.preferences.set("launcherNumberKeys", on: false)
        drain()
        for digit in 1...10 {
            precondition(controller.launcherRow(digit: digit, query: "sa", entryRows: rows) == nil, "off again")
        }
        controller.stop()
        print("nc-NumberKeys-wiring-test: ok")
    }
}
