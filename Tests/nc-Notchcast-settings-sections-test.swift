// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit
import CoreGraphics
import SwiftUI

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Rows drawn one per run-time command, as Taildrop's per-device rows are.
enum DevicesAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "devices", title: "Devices", subtitle: "", category: .files),
        NotchcastSwitch(id: "plainRows", title: "Plain", subtitle: "", category: .files),
    ]
    static let settings = [
        NotchcastSettingsRow(switchID: "devices", isEmpty: { $0.commands.isEmpty }) { _ in AnyView(EmptyView()) },
        NotchcastSettingsRow(switchID: "plainRows") { _ in AnyView(EmptyView()) },
    ]
}

@main
enum NotchcastSettingsSectionsTests {
    @MainActor
    static func main() {
        let suite = "nc-Notchcast-settings-sections-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        let controller = NotchcastController(
            addons: [DevicesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: SilentPresenter())
        controller.preferences.set("devices", on: true)
        controller.preferences.set("plainRows", on: true)
        func sections() -> [String] {
            NotchcastSettingsLayout(switches: controller.switches).groups(
                in: .clipboardFiles, isEnabled: controller.preferences.isEnabled, withCommands: [],
                withRows: controller.settingsRowOwners
            ).flatMap { $0.details.map(\.title) }
        }
        precondition(sections() == ["Plain"], "a feature whose rows draw nothing has no section, got \(sections())")
        controller.context(forSwitch: "devices")!.setCommands([
            NotchcastCommand(slug: "to-studio", name: "Studio", symbol: "laptopcomputer", switchID: "devices") { _ in },
        ])
        precondition(sections() == ["Devices", "Plain"], "its section returns with a row, got \(sections())")
        print("PASSED")
    }
}
