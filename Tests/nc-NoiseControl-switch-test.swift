// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/NoiseControlAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlSwitcher.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation
import Synchronization

/// A scripted Sound menu on a virtual clock: `pause` advances time, nothing really waits.
final class FakeMenu: Sendable {
    struct State {
        var clock: Duration = .zero
        var buttons: [NoiseControlButton] = []
        var hiddenReads = 0
        var pressSelects = true
        var openFailure: NoiseControlFailure?
        var steps: [NoiseControlSwitcher.Step] = []
    }

    let state = Mutex(State())

    func reset(_ buttons: [NoiseControlButton]) { state.withLock { $0 = State(buttons: buttons) } }
    var steps: [NoiseControlSwitcher.Step] { state.withLock { $0.steps } }

    func perform(_ step: NoiseControlSwitcher.Step) throws -> [NoiseControlButton] {
        try state.withLock { state in
            state.steps.append(step)
            switch step {
            case .open:
                if let failure = state.openFailure { throw failure }
            case .read:
                guard state.hiddenReads == 0 else {
                    state.hiddenReads -= 1
                    return []
                }
                return state.buttons
            case .press(let mode):
                guard state.pressSelects else { break }
                state.buttons = state.buttons.map { button in
                    NoiseControlButton(mode: button.mode, selected: button.selected.map { _ in button.mode == mode })
                }
            case .close:
                break
            }
            return []
        }
    }

    var switcher: NoiseControlSwitcher {
        NoiseControlSwitcher(
            perform: { step, _ in try self.perform(step) },
            pause: { self.state.withLock { $0.clock += .milliseconds(50) } },
            now: { self.state.withLock { $0.clock } })
    }
}

func menu(_ modes: [NoiseControlMode], selected: NoiseControlMode?) -> [NoiseControlButton] {
    modes.map { NoiseControlButton(mode: $0, selected: $0 == selected) }
}

let full: [NoiseControlMode] = [.off, .transparency, .adaptive, .noiseCancellation]
let fakeMenu = FakeMenu()

@MainActor
final class FakeOutput {
    var modelUID: String? = "2014 4c"
    var trusted = true
    var changed: (@MainActor @Sendable () -> Void)?
}

@MainActor let output = FakeOutput()

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.
extension NoiseControlSystem {
    static var live: Self {
        Self(
            outputModelUID: { output.modelUID },
            watchOutput: { changed in
                output.changed = changed
                return NSObject()
            },
            switcher: fakeMenu.switcher)
    }
}

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
final class NoticeLog: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@main
@MainActor
enum NoiseControlSwitchTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        headsets()
        policy()
        await switcher()
        await module()
        print("\(checks) noise control checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func headsets() {
        let adaptive: [NoiseControlMode] = [.noiseCancellation, .transparency, .adaptive, .off]
        check("AirPods Pro 2 offers every mode", NoiseControlHeadset.modes(modelUID: "2014 4c") == adaptive)
        check("AirPods Pro 3 offers every mode", NoiseControlHeadset.modes(modelUID: "2027 4c") == adaptive)
        check("hex case does not matter", NoiseControlHeadset.modes(modelUID: "201B 4C") == adaptive)
        check("AirPods Pro offers no Adaptive",
              NoiseControlHeadset.modes(modelUID: "200e 4c") == [.noiseCancellation, .transparency, .off])
        check("AirPods Max offers no Adaptive",
              NoiseControlHeadset.modes(modelUID: "200a 4c") == [.noiseCancellation, .transparency, .off])
        for uid in ["200f 4c", "2014 5ac", "2014", "2014 4c extra", "", "speakers"] {
            check("\(uid) offers nothing", NoiseControlHeadset.modes(modelUID: uid).isEmpty)
        }
        check("no output offers nothing", NoiseControlHeadset.modes(modelUID: nil).isEmpty)
    }

    static func policy() {
        check("every mode plus the cycle, in launcher order",
              NoiseControlPolicy.requests(offered: [.off, .adaptive, .transparency, .noiseCancellation])
                  == [.set(.noiseCancellation), .set(.transparency), .set(.adaptive), .set(.off), .cycle])
        check("a headset without Adaptive still cycles",
              NoiseControlPolicy.requests(offered: [.noiseCancellation, .transparency, .off])
                  == [.set(.noiseCancellation), .set(.transparency), .set(.off), .cycle])
        check("one cycling mode has no cycle", NoiseControlPolicy.requests(offered: [.noiseCancellation, .off])
              == [.set(.noiseCancellation), .set(.off)])
        check("no headset, no commands", NoiseControlPolicy.requests(offered: []).isEmpty)

        let order: [(NoiseControlMode?, NoiseControlMode)] = [
            (.noiseCancellation, .transparency), (.transparency, .adaptive), (.adaptive, .noiseCancellation),
            (.off, .noiseCancellation), (nil, .noiseCancellation),
        ]
        for (current, next) in order {
            check("cycle from \(String(describing: current)) goes to \(next)",
                  NoiseControlPolicy.target(for: .cycle, in: menu(full, selected: current)) == next)
        }
        let basic: [NoiseControlMode] = [.off, .transparency, .noiseCancellation]
        check("without Adaptive, Transparency cycles back",
              NoiseControlPolicy.target(for: .cycle, in: menu(basic, selected: .transparency)) == .noiseCancellation)
        check("a menu with one cycling mode cannot cycle",
              NoiseControlPolicy.target(for: .cycle, in: menu([.off, .noiseCancellation], selected: .off)) == nil)
        check("a listed mode is the target", NoiseControlPolicy.target(for: .set(.off), in: menu(basic, selected: nil)) == .off)
        check("an unlisted mode is no target",
              NoiseControlPolicy.target(for: .set(.adaptive), in: menu(basic, selected: nil)) == nil)
    }

    static func outcome(_ request: NoiseControlRequest) async -> Result<NoiseControlMode, any Error> {
        do { return .success(try await fakeMenu.switcher.run(request)) } catch { return .failure(error) }
    }

    static func failure(_ result: Result<NoiseControlMode, any Error>) -> NoiseControlFailure? {
        if case .failure(let error) = result { return error as? NoiseControlFailure }
        return nil
    }

    static func switcher() async {
        fakeMenu.reset(menu(full, selected: .noiseCancellation))
        fakeMenu.state.withLock { $0.hiddenReads = 2 }
        var result = await outcome(.set(.transparency))
        check("a set switches once the menu shows", (try? result.get()) == .transparency)
        check("it waits for the menu, presses, confirms and closes",
              fakeMenu.steps == [.open, .read, .read, .read, .press(.transparency), .read, .close])

        fakeMenu.reset(menu(full, selected: .adaptive))
        result = await outcome(.set(.adaptive))
        check("the current mode needs no press", (try? result.get()) == .adaptive && fakeMenu.steps == [.open, .read, .close])

        fakeMenu.reset(menu(full, selected: .transparency))
        result = await outcome(.cycle)
        check("cycle presses the next mode", (try? result.get()) == .adaptive && fakeMenu.steps.contains(.press(.adaptive)))

        fakeMenu.reset(full.map { NoiseControlButton(mode: $0, selected: nil) })
        result = await outcome(.set(.off))
        check("a menu reporting no state is trusted after the press",
              (try? result.get()) == .off && fakeMenu.steps == [.open, .read, .press(.off), .close])

        fakeMenu.reset([])
        result = await outcome(.set(.transparency))
        check("a menu without noise control fails, never hangs", failure(result) == .notInMenu)
        check("it gives up at the deadline and still closes",
              fakeMenu.steps.count(where: { $0 == .read }) == 60 && fakeMenu.steps.last == .close)

        fakeMenu.reset(menu(full, selected: .noiseCancellation))
        fakeMenu.state.withLock { $0.pressSelects = false }
        result = await outcome(.set(.transparency))
        check("a press that never takes times out", failure(result) == .timedOut && fakeMenu.steps.last == .close)

        fakeMenu.reset(menu([.off, .transparency, .noiseCancellation], selected: .off))
        result = await outcome(.set(.adaptive))
        check("a mode the menu lacks fails and closes",
              failure(result) == .modeUnavailable && fakeMenu.steps == [.open, .read, .close])

        fakeMenu.reset(menu(full, selected: .off))
        fakeMenu.state.withLock { $0.openFailure = .menuUnavailable }
        result = await outcome(.set(.transparency))
        check("no Sound menu fails without a close", failure(result) == .menuUnavailable && fakeMenu.steps == [.open])

        fakeMenu.reset(menu(full, selected: .off))
        let cancelled = Task { await outcome(.set(.transparency)) }
        cancelled.cancel()
        result = await cancelled.value
        check("a cancelled switch stops before pressing and closes",
              !fakeMenu.steps.contains(.press(.transparency)) && fakeMenu.steps.last == .close)
        if case .failure(let error) = result { check("cancellation stays cancellation", error is CancellationError) }
    }

    static func module() async {
        let suite = "nc-NoiseControl-switch-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let presenter = NoticeLog()
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { output.trusted }, makeSession: { FakeSession($0) })
        var controller = NotchcastController(
            addons: [NoiseControlAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
        controller.start()
        check("off by default", NoiseControlAddon.switches[0].defaultEnabled == false && controller.enabledCommands.isEmpty)
        check("it needs Accessibility", NoiseControlAddon.switches[0].requiredGrants == [.accessibility])
        controller.stop()

        defaults.set(true, forKey: NoiseControlAddon.switchID)
        controller = NotchcastController(
            addons: [NoiseControlAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
        var launcher: [String] = []
        controller.onCommandsChanged = { launcher = controller.launcherCommands($0).map(\.id) }
        controller.start()
        let all = ["noise-cancellation", "transparency", "adaptive", "noise-control-off", "cycle-noise-control"]
            .map { "command:nc-" + $0 }
        check("frozen command ids", NoiseControlAddon.commands.map(\.id) == all)
        check("AirPods Pro 2 lists every command", launcher == all)

        output.modelUID = "200e 4c"
        output.changed?()
        check("AirPods Pro drops Adaptive from the launcher", launcher == all.filter { $0 != "command:nc-adaptive" })
        output.modelUID = nil
        output.changed?()
        check("no headset, no launcher commands", launcher.isEmpty)
        check("hotkeys stay bound with no headset", controller.enabledCommands.count == all.count)

        let module = controller.context(forSwitch: NoiseControlAddon.switchID)?.module(NoiseControlModule.self)
        check("a hotkey with no headset reports it", controller.run(entryID: "command:nc-transparency")
              && presenter.posts.last?.text == NoiseControlFailure.noHeadset.errorDescription
              && presenter.posts.last?.isFailure == true && module?.switchTask == nil)

        output.modelUID = "200e 4c"
        _ = controller.run(entryID: "command:nc-adaptive")
        check("a mode the headset lacks reports it",
              presenter.posts.last?.text == NoiseControlFailure.modeUnavailable.errorDescription)

        output.trusted = false
        _ = controller.run(entryID: "command:nc-transparency")
        check("no Accessibility reports it",
              presenter.posts.last?.text == NoiseControlFailure.needsAccessibility.errorDescription)
        output.trusted = true

        fakeMenu.reset(menu([.off, .transparency, .noiseCancellation], selected: .noiseCancellation))
        _ = controller.run(entryID: "command:nc-transparency")
        let running = module?.switchTask
        _ = controller.run(entryID: "command:nc-noise-control-off")
        await running?.value
        check("the result is a notice named after the mode", presenter.posts.last?.text == "Transparency"
              && presenter.posts.last?.symbol == NoiseControlRequest.set(.transparency).symbol
              && presenter.posts.last?.isFailure == false && presenter.posts.last?.id == NoiseControlModule.noticeID)
        check("a second press while switching is dropped", fakeMenu.steps.count(where: { $0 == .open }) == 1)

        fakeMenu.reset(menu([.off, .transparency, .noiseCancellation], selected: .transparency))
        let posts = presenter.posts.count
        _ = controller.run(entryID: "command:nc-cycle-noise-control")
        let stopped = module?.switchTask
        controller.stop()
        await stopped?.value
        check("switching off mid-run posts nothing and ends the notice",
              presenter.posts.count == posts && presenter.ends.last == NoiseControlModule.noticeID)
    }
}
