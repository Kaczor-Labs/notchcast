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

enum OffCommandAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "probeMain", title: "Probe", subtitle: "", category: .launcher),
        NotchcastSwitch(id: "probeChild", title: "Child", subtitle: "", category: .launcher,
                        dependencies: ["probeMain"]),
    ]
    static let commands = [
        NotchcastCommand(slug: "probe-run", name: "Probe", symbol: "circle", switchID: "probeMain") { context in
            context.presenter.post(IslandNotice(id: "probe", text: "Probe ran"), onTap: nil)
        },
        NotchcastCommand(slug: "probe-child", name: "Probe Child", symbol: "circle", switchID: "probeChild") { _ in },
    ]
}

@main
@MainActor
struct NotchcastModuleCommandsTest {
    /// Reconcile hops through the main queue, so the run loop must turn.
    static func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func offCommands(_ defaults: UserDefaults) {
        let presenter = RecordingPresenter()
        let system = FakeSystem()
        let controller = NotchcastController(
            addons: [OffCommandAddon.self], defaults: defaults, hub: system.makeHub(),
            dictation: FakeDictation(), presenter: presenter)
        var published: [[String]] = []
        controller.onCommandsChanged = { published.append($0.map(\.id)) }
        controller.start()
        let commandID = "command:nc-probe-run"
        let childID = "command:nc-probe-child"
        let noticeID = "notchcast.commandOff"
        let post = "post \(noticeID) Probe is off"
        precondition(published == [[]] && controller.offCommands.map(\.id).contains(commandID),
                     "an off command keeps its hotkey")
        precondition(controller.press(entryID: commandID) && presenter.log == [post],
                     "pressing an off command says it is off")
        var openedSwitch: String?
        controller.openSwitch = { openedSwitch = $0.id }
        presenter.noticeTaps[noticeID]?()
        precondition(openedSwitch == "probeMain", "the notice's click opens Settings at the command's switch")
        precondition(controller.press(entryID: commandID) && presenter.log == [post, post],
                     "a second press replaces the notice")
        precondition(!controller.press(entryID: "command:nc-nope"), "an id no add-on declares is not ours")
        precondition(controller.switchOff(for: childID)?.id == "probeChild",
                     "a command whose own switch is off names that switch")

        controller.stop()
        controller.preferences.set("probeChild", on: true)
        controller.start()
        precondition(controller.switchOff(for: childID)?.id == "probeMain",
                     "a command behind an off dependency names that dependency")

        controller.stop()
        controller.preferences.set("probeMain", on: true)
        controller.start()
        precondition(controller.press(entryID: commandID) && presenter.log == [post, post, "post probe Probe ran"],
                     "an enabled command presses through")
        controller.stop()
    }

    static func main() {
        let suite = "nc-module-commands-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        offCommands(defaults)
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
        precondition(published == [[], ["command:nc-publish-run"]], "a module's own command is published: \(published)")
        precondition(
            controller.slots[0].commands.map(\.name) == ["Published"], "the add-on's rows list it")
        precondition(controller.run(entryID: "command:nc-publish-run"), "run(entryID:) finds it")
        precondition(presenter.log == ["post publish Published ran"], "it ran on its own context: \(presenter.log)")

        controller.preferences.set("publishMain", on: false)
        drain()
        precondition(published.last == [], "it is withdrawn once the switch goes off")
        precondition(controller.context(forSwitch: "publishMain")?.commands.isEmpty == true, "the context drops it")
        precondition(!controller.run(entryID: "command:nc-publish-run"), "a withdrawn command no longer runs")
        precondition(
            !controller.press(entryID: "command:nc-publish-run") && presenter.log == ["post publish Published ran"],
            "a run-time command is unknown once its module stops")
        controller.stop()
        print("PASS Notchcast commands: off notices, switch targeting, and run-time publication")
    }
}
