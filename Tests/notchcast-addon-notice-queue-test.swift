// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandMeetingExpansion.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenter.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
import AppKit
import Foundation

/// Only what IslandPresenter reaches on AppCore, so the shipped presenter runs without the app.
@MainActor
final class AppCore {
    static let shared = AppCore()
    let island = StubIsland()
    let palette = StubPalette()
    var isShowingDialog = false
}

@MainActor final class StubPalette { var isVisible = false }

@MainActor
final class StubIsland {
    let resting: IslandController? = IslandController()
    let overlays = StubOverlays()
}

@MainActor final class StubOverlays { func placeReport(_ panel: NSPanel, screen: NSScreen?) {} }

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

final class IslandLevelBand: NSView { var art: IslandLevelArt? }

struct IslandLevelArt {
    init(_ level: IslandLevel, notch: Bool) {}
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
            context.presenter.post(IslandNotice(id: "keepAwake", text: "Keeping Your Mac Awake"), onTap: nil)
        },
    ]
}

@main @MainActor
struct AddonNoticeQueueTest {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool) {
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func turn(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    static func main() {
        _ = NSApplication.shared
        let suite = "nc-notice-queue-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let system = FakeSystem()
        let controller = NotchcastController(addons: [MusicNoticeAddon.self, AwakeNoticeAddon.self],
                                             defaults: defaults, hub: system.makeHub(), presenter: IslandPresenter())
        controller.start()
        controller.preferences.set("musicNotice", on: true)
        controller.preferences.set("awakeNotice", on: true)
        for _ in 0..<5 { turn(0.01) }
        let pill = AppCore.shared.island.resting!
        let first = "Couldn't Stop Apple Music Opening"
        let second = "Keeping Your Mac Awake"

        check("the first add-on notice runs", controller.run(entryID: "command:nc-music-notice"))
        check("the second add-on notice runs", controller.run(entryID: "command:nc-awake-notice"))
        print("shown right after both posts: \(pill.shown); showing: \(pill.notice?.text ?? "nothing")")
        check("the newer notice shows on top", pill.notice?.text == second)
        let deadline = Date().addingTimeInterval(10)
        while pill.notice?.text != first, Date() < deadline { turn(0.05) }
        print("shown after dwell: \(pill.shown)")
        check("the first notice returns once the second dwells out", pill.shown == [first, second, first])
        controller.stop()
        print(failures == 0 ? "PASS AddonNoticeQueueTest" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
