// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit
import Observation
import os

/// Publishes a command of its own on start, as a module does for what it learns at run time.
@MainActor
final class PublishingModule: NotchcastModule {
    let context: NotchcastContext

    init(_ context: NotchcastContext) { self.context = context }

    func start() {
        context.setCommands([
            NotchcastCommand(slug: "publish-run", name: "Published", symbol: "circle", switchID: "publishMain") {
                $0.presenter.post(IslandNotice(id: "publish", text: "Published ran"), onTap: nil)
            },
        ])
    }

    func stop() {}
}

enum PublishingAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "publishMain", title: "Publish", subtitle: "", category: .launcher)]
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { PublishingModule(context) }
}

/// Pins the commands a running module adds: published, found by `run(entryID:)`, gone with the switch.
@main
@MainActor
struct NotchcastModuleCommandsTest {
    /// Reconcile hops through the main queue, so the run loop must turn.
    static func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func main() {
        let suite = "nc-module-commands-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let presenter = RecordingPresenter()
        let system = FakeSystem()
        let controller = NotchcastController(
            addons: [PublishingAddon.self], defaults: defaults, hub: system.makeHub(),
            dictation: FakeDictation(), presenter: presenter)
        var published: [[String]] = []
        controller.onCommandsChanged = { published.append($0.map(\.id)) }
        controller.start()
        precondition(!controller.run(entryID: "command:nc-publish-run"), "a module's commands wait for its switch")

        let observed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = controller.slots[0].commands } onChange: { observed.withLock { $0 = true } }
        controller.preferences.set("publishMain", on: true)
        drain()
        precondition(observed.withLock { $0 }, "a view reading the add-on's commands redraws on setCommands")
        precondition(published == [["command:nc-publish-run"]], "a module's own command is published: \(published)")
        precondition(
            controller.slots[0].commands.map(\.name) == ["Published"], "the add-on's rows list it")
        precondition(controller.run(entryID: "command:nc-publish-run"), "run(entryID:) finds it")
        precondition(presenter.log == ["post publish Published ran"], "it ran on its own context: \(presenter.log)")

        controller.preferences.set("publishMain", on: false)
        drain()
        precondition(published.last == [], "it is withdrawn once the switch goes off")
        precondition(controller.context(forSwitch: "publishMain")?.commands.isEmpty == true, "the context drops it")
        precondition(!controller.run(entryID: "command:nc-publish-run"), "a withdrawn command no longer runs")
        controller.stop()
        print("PASS Notchcast module commands: published, run by entry id, gone with the switch")
    }
}
