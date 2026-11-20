// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit

/// Pins the v1 id, one tap per start, and that only a live tap's key may block a launch.
@main
struct MusicBlockModuleTests {
    @MainActor
    static func main() {
        switchShape()
        lifecycle()
        tapLiveness()
        print("Music block module: v1 switch id, one tap per start, blocks only while the tap is live")
    }

    @MainActor
    static func switchShape() {
        precondition(MusicBlockAddon.switches.map(\.id) == ["musicBlockAppleMusic"], "the v1 raw value stays")
        let entry = MusicBlockAddon.switches[0]
        precondition(entry.defaultEnabled && entry.category == .music && entry.requiredGrants == [.accessibility])
    }

    @MainActor
    static func lifecycle() {
        let suite = "nc-musicblock-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        var changes = 0
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: MusicBlockAddon.switches),
            presenter: SilentPresenter(), hub: hub,
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { .now }, onTapsChanged: { changes += 1 })
        guard let module = MusicBlockAddon.makeModule(context) else { preconditionFailure("no module") }

        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 1)
        let tap = context.wantedTaps.first!.tap
        precondition(tap.switchID == "musicBlockAppleMusic" && tap.reset != nil)
        precondition(tap.mask == NotchcastTapPolicy.mask(rawType: NotchcastMediaKey.eventType), "media keys only")
        guard case .observe = tap.handler else { preconditionFailure("a media key is only observed, never held") }
        tap.reset?()

        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 1, "a second start claims nothing more")
        module.stop()
        precondition(context.wantedTaps.isEmpty && changes == 2, "stop releases the tap")
        module.stop()
        precondition(changes == 2, "a second stop is a no-op")
        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 3, "a restart claims it again")
        module.stop()
    }
}

extension MusicBlockModuleTests {
    @MainActor
    static func tapLiveness() {
        let suite = "nc-musicblock-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let system = FakeSystem()
        let subscriptions = Subscriptions(system.makeHub())
        let presenter = RecordingPresenter()
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: MusicBlockAddon.switches),
            presenter: presenter, hub: subscriptions.hub,
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { .now }, onTapsChanged: {})
        let module = MusicBlockModule(context: context, gestureAge: { .infinity }, isMusicRunning: { false })
        module.start()
        defer { module.stop() }
        let tap = context.wantedTaps[0].tap
        subscriptions.add(tap)
        guard case .observe(let deliver) = tap.handler else { preconditionFailure("observed") }
        func pressPlay() {
            let ns = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: 16 << 16 | 0x0A << 8, data2: -1)!
            let event = ns.cgEvent!
            event.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            deliver(NotchcastTapEvent(type: event.type, event: event, syntheticTag: syntheticTag))
        }
        func launch(_ processID: pid_t) -> Bool {
            let music = FakeMusic(processID)
            module.launched(music)
            return music.stopped
        }

        precondition(context.isTapLive)
        pressPlay()
        precondition(launch(101), "a play key just seen on a live tap blocks the launch")
        precondition(!launch(102), "no key, no block")

        pressPlay()
        system.sessions.last!.failInstall()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(!context.isTapLive)
        subscriptions.hub.refreshPermission()
        precondition(context.isTapLive)
        precondition(!launch(103), "the reset on a lost session disarms the key heard before it")

        system.sessions.last!.failInstall()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(!context.isTapLive)
        pressPlay()
        precondition(!launch(104), "while the tap is not live, no launch is blocked")
        precondition(presenter.log.isEmpty, "a launch left alone posts nothing")
    }
}

/// Stands in for a launching Apple Music; stopping it only records the call.
private final class FakeMusic: NSRunningApplication {
    private let pid: pid_t
    private(set) var stopped = false
    init(_ pid: pid_t) {
        self.pid = pid
        super.init()
    }
    override var bundleIdentifier: String? { "com.apple.Music" }
    override var processIdentifier: pid_t { pid }
    override func forceTerminate() -> Bool {
        stopped = true
        return true
    }
    override func terminate() -> Bool { forceTerminate() }
}

@MainActor
private final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { preconditionFailure("no notice: \(notice.text)") }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
