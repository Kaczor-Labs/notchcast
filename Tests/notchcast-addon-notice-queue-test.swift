// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandMeetingExpansion.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenter.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit
import Foundation
import Observation

/// Only what IslandPresenter reaches on AppCore, so the shipped presenter runs without the app.
@MainActor @Observable
final class AppCore {
    static let shared = AppCore()
    let island = StubIsland()
    let palette = StubPalette()
    var isShowingDialog = false
}

@MainActor @Observable final class StubPalette { var isVisible = false }

@MainActor
final class StubIsland {
    var resting: IslandController? = IslandController()
    let overlays = StubOverlays()
    let pillMenu = StubPillMenu()
    func frosted(on screen: NSScreen?) -> Bool { false }
}

@MainActor final class StubOverlays { func placeReport(_ panel: NSPanel, screen: NSScreen?) {} }
@MainActor final class StubPillMenu { func refit(keepingSelection: Bool = false) {} }

/// The resting pill: `shown` is every notice it was handed, in order.
@MainActor
final class IslandController {
    var shown: [String] = []
    var notice: IslandNotice? { didSet { if let notice, notice != oldValue { shown.append(notice.text) } } }
    var statuses: [IslandStatus] = []
    var level: IslandLevel?
    var expanded = false
    var glance: String?
}

final class HUDPanel: NSPanel {
    func fadeIn(duration: TimeInterval, order: () -> Void) {}
    func fadeOut(duration: TimeInterval) {}
    func cancelFade() {}
}

final class IslandLevelBand: NSView { var art: IslandLevelArt?; func restyle(frosted: Bool) {} }

struct IslandLevelArt {
    init(_ level: IslandLevel, notch: Bool, frosted: Bool) {}
    var bandSize: CGSize { .zero }
}

enum Theme { enum Duration { static let enter: TimeInterval = 0; static let exit: TimeInterval = 0 } }

enum MusicNoticeAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "musicNotice", title: "Music", subtitle: "", category: .notices)]
    static let commands = [
        NotchcastCommand(slug: "music-notice", name: "Music", symbol: "circle", switchID: "musicNotice") { context in
            context.presenter.post(
                IslandNotice(id: "musicBlock", text: "Couldn't Stop Apple Music Opening", isFailure: true), onTap: nil)
        },
    ]
}

enum AwakeNoticeAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "awakeNotice", title: "Awake", subtitle: "", category: .notices)]
    static let commands = [
        NotchcastCommand(slug: "awake-notice", name: "Awake", symbol: "circle", switchID: "awakeNotice") { context in
            context.presenter.post(IslandNotice(id: "awakeNotice", text: "Keeping Your Mac Awake"), onTap: nil)
        },
    ]
}

/// Time moves only when the test says so; a sleeper wakes on the main actor at its own deadline.
@MainActor
final class ManualClock {
    /// Whole milliseconds, so a deadline lands on the dwell rather than a rounding error off it.
    private var tick = 0
    private var sleepers: [(deadline: Int, wake: CheckedContinuation<Void, Never>)] = []

    var now: TimeInterval { TimeInterval(tick) / 1000 }

    func sleep(_ seconds: TimeInterval) async {
        let deadline = tick + max(Int((seconds * 1000).rounded()), 1)
        await withCheckedContinuation { sleepers.append((deadline, $0)) }
    }

    /// Lets tasks already started go to sleep first, then wakes each due one in deadline order.
    func advance(by seconds: TimeInterval) async {
        await settle()
        let target = tick + Int((seconds * 1000).rounded())
        while let next = sleepers.indices.min(by: { sleepers[$0].deadline < sleepers[$1].deadline }),
              sleepers[next].deadline <= target {
            let sleeper = sleepers.remove(at: next)
            tick = max(tick, sleeper.deadline)
            sleeper.wake.resume()
            await settle()
        }
        tick = target
        await settle()
    }

    /// Every presenter task runs on the main actor, so yielding drains them in order.
    func settle() async { for _ in 0..<10 { await Task.yield() } }
}

@main @MainActor
struct AddonNoticeQueueTest {
    static var failures = 0
    static let clock = ManualClock()

    static func check(_ label: String, _ ok: Bool) {
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static let dwell: TimeInterval = 2.4 // the stock message HUD dwell add-ons were promised
    static let step: TimeInterval = 0.01

    /// An `uncover` that adds a pill hands it over as IslandCoordinator.rebuild does.
    static func checkHeld(_ label: String, _ text: String, run: () -> Bool, cover: () -> Void,
                          uncover: () -> IslandController?) async {
        cover()
        await clock.settle()
        check("\(label): the add-on notice runs", run())
        await clock.advance(by: dwell + 1)
        let pill = uncover()
        await clock.settle()
        print("\(label): showing once uncovered: \(pill?.notice?.text ?? "nothing")")
        check("\(label): the notice did not expire unseen", pill?.notice?.text == text)
        let dwell = pill?.notice?.dwell ?? Self.dwell
        await clock.advance(by: dwell - step)
        check("\(label): it still shows just before a full dwell", pill?.notice?.text == text)
        await clock.advance(by: step)
        check("\(label): it goes exactly at a full dwell once seen", pill?.notice == nil)
    }

    static func main() async {
        _ = NSApplication.shared
        let suite = "nc-notice-queue-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let system = FakeSystem()
        let presenter = IslandPresenter(now: { clock.now }, sleep: { await clock.sleep($0) })
        let controller = NotchcastController(addons: [MusicNoticeAddon.self, AwakeNoticeAddon.self],
                                             defaults: defaults, hub: system.makeHub(),
                                             dictation: FakeDictation(), presenter: presenter)
        controller.start()
        controller.preferences.set("musicNotice", on: true)
        controller.preferences.set("awakeNotice", on: true)
        await clock.settle()
        let pill = AppCore.shared.island.resting!
        let first = "Couldn't Stop Apple Music Opening"
        let second = "Keeping Your Mac Awake"

        check("the first add-on notice runs", controller.run(entryID: "command:nc-music-notice"))
        check("the second add-on notice runs", controller.run(entryID: "command:nc-awake-notice"))
        print("shown right after both posts: \(pill.shown); showing: \(pill.notice?.text ?? "nothing")")
        check("the newer notice shows on top", pill.notice?.text == second)
        await clock.advance(by: dwell - step)
        check("the newer notice still shows just before its dwell ends", pill.notice?.text == second)
        await clock.advance(by: step)
        print("shown once the newer notice dwelled out: \(pill.shown)")
        check("the first notice returns exactly when the second dwells out", pill.shown == [first, second, first])
        await clock.advance(by: 10)
        check("the queue empties", pill.notice == nil)
        let core = AppCore.shared
        let music = { controller.run(entryID: "command:nc-music-notice") }
        await checkHeld("launcher", first, run: music, cover: { core.palette.isVisible = true }) {
            core.palette.isVisible = false
            return core.island.resting
        }
        await checkHeld("question", second, run: { controller.run(entryID: "command:nc-awake-notice") },
                        cover: { core.isShowingDialog = true }) {
            core.isShowingDialog = false
            return core.island.resting
        }
        await checkHeld("no display", first, run: music, cover: { core.island.resting = nil }) {
            let arrived = IslandController()
            core.island.resting = arrived
            presenter.restore(arrived, resting: true)
            presenter.restingChanged()
            return arrived
        }
        controller.stop()
        print(failures == 0 ? "PASS AddonNoticeQueueTest" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
