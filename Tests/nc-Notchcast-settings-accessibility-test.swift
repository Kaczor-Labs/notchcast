// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastSwitch.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsView.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastIslandSettingsRows.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastCommandRowLayout.swift
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/MusicBlockAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/UI/ScreenshotsSettingsView.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPosition.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsScrollTarget.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsHistory.swift Tinycast/Features/Settings/SettingsNavigationState.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/Platform/Appearance.swift
import AppKit
import SwiftUI

@main
@MainActor
struct NotchcastSettingsAccessibilityTests {
    static func main() {
        _ = NSApplication.shared
        let suite = "NotchcastSettingsAccessibilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let music = MusicBlockAddon.switches
        let capture = CaptureFixture.switches
        let controller = NotchcastController([MusicBlockAddon.self, CaptureFixture.self], defaults: defaults)
        let cases: [(NotchcastPane, [String])] = [
            (.displaySound, music.map(\.title)),
            (.capture, capture.map(\.title) + ["Edit after capture"]),
            (.island, [
                NotchcastSettingsSearch.showsInCaptures.resolved(),
                NotchcastSettingsSearch.outlineWhenOpen.resolved(),
                NotchcastSettingsSearch.opensOnHover.resolved(),
            ]),
        ]
        var passed = true
        for (pane, titles) in cases {
            let names = switchNames(in: pane, controller: controller)
            if names.sorted() != titles.sorted() {
                print("FAIL \(pane.title) switch names. Expected \(titles), got \(names)")
                passed = false
            }
        }
        if let parent = music.first {
            controller.preferences.set(parent.id, on: false)
            let names = switchNames(in: .displaySound, controller: controller)
            if names.sorted() != music.map(\.title).sorted() {
                print("FAIL Music Block switch names with the parent off. Expected \(music.map(\.title)), got \(names)")
                passed = false
            }
        }
        if !passed { exit(1) }
        print("PASS Settings accessibility names for Music Block, the capture child row and the Island switches")
    }

    static func switchNames(in pane: NotchcastPane, controller: NotchcastController) -> [String] {
        let view = NotchcastSettingsView(controller: controller, pane: pane)
            .environment(SettingsNavigationState(tab: .notchcast(pane)))
            .environment(AppSettings())
            .environment(\.colorScheme, .dark)
        let frame = NSRect(x: 0, y: 0, width: 750, height: 500)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return withExtendedLifetime(window) {
            (host.accessibilityChildren() ?? []).flatMap { switchNames(below: $0) }
        }
    }

    static func switchNames(below node: Any) -> [String] {
        guard let element = node as? any NSAccessibilityProtocol else { return [] }
        if element.accessibilityRole() == .checkBox || element.accessibilitySubrole() == .switch {
            let label = element.accessibilityLabel() ?? ""
            return [label.isEmpty ? (element.accessibilityTitle() ?? "") : label]
        }
        return (element.accessibilityChildren() ?? []).flatMap { switchNames(below: $0) }
    }
}

// Keep the production form and row titles while leaving system services out of the harness.
@MainActor
final class NotchcastController {
    struct Slot {
        let addon: any NotchcastAddon.Type
        let settings: [SettingsEntry]
    }

    struct SettingsEntry: Identifiable {
        let id = UUID()
        let row: NotchcastSettingsRow
    }

    struct Hub {
        let isTrusted = true
        func refreshPermission() {}
    }

    let switches: [NotchcastSwitch]
    let preferences: NotchcastPreferences
    let slots: [Slot]
    let hub = Hub()
    private let context: NotchcastContext

    init(_ addons: [any NotchcastAddon.Type], defaults: UserDefaults) {
        switches = addons.flatMap { $0.switches }
        preferences = NotchcastPreferences(defaults: defaults, switches: switches)
        slots = addons.map { Slot(addon: $0, settings: $0.settings.map { SettingsEntry(row: $0) }) }
        context = NotchcastContext(defaults: defaults)
    }

    func context(forSwitch id: String) -> NotchcastContext? { context }
}

enum CaptureFixture: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "capture", title: "Capture", subtitle: "Save an image",
                        category: .capture, defaultEnabled: true)
    ]
    static let settings = [
        NotchcastSettingsRow(switchID: "capture") { AnyView(ScreenshotsSettingsView(defaults: $0.defaults)) }
    ]
}

struct NotchcastContext { let defaults: UserDefaults }
struct NotchcastTap: Sendable {}

final class MusicBlockModule: NotchcastModule {
    init(context: NotchcastContext) {}
    func start() {}
    func stop() {}
}

enum ScreenshotsModule {
    static let editAfterCaptureKey = "editAfterCapture"
}

@MainActor
@Observable
final class AppSettings {
    var islandShowsInCaptures = true
    var islandOutlineWhenOpen = false
    var islandOpensOnHover = false
    var islandPosition = IslandPosition.topEdge
}

@MainActor
enum AppCore {
    static let shared = AppCoreFixture()
}
struct AppCoreFixture { let island = IslandFixture() }
struct IslandFixture { let looks = false }
struct NotchcastLookSection: View {
    let looks: Bool
    var body: some View { EmptyView() }
}

enum Permissions {
    static func openAccessibilitySettings() {}
}

struct AliasField: View {
    let key: String
    let name: String
    var body: some View { EmptyView() }
}

struct ShortcutRecorder: View {
    enum Action { case notchcastCommand(entryID: String) }
    let action: Action
    var body: some View { EmptyView() }
}

extension View {
    func launcherVisibilityHelp() -> some View { self }
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}
