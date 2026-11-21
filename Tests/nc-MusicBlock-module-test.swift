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
    static func main() async {
        switchShape()
        lifecycle()
        tapLiveness()
        await resume()
        await resumeFailures()
        print("Music block module: v1 switch id, one tap per start, blocks only while the tap is live,"
              + " resumes the last player, tells a refusal")
    }

    @MainActor
    static func switchShape() {
        precondition(MusicBlockAddon.switches.map(\.id) == ["musicBlockAppleMusic", "musicBlockResumeLastPlayer"],
                     "the v1 raw value stays")
        let entry = MusicBlockAddon.switches[0]
        precondition(entry.defaultEnabled && entry.category == .music && entry.requiredGrants == [.accessibility])
        let resume = MusicBlockAddon.switches[1]
        precondition(resume.defaultEnabled && resume.dependencies == [entry.id] && resume.category == .music,
                     "on by default, and only while the block is on")
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

/// A module on a fake system whose play key is pressed, then Music launches, as the media key does it.
@MainActor
private final class ResumeRig {
    let defaults: UserDefaults
    let suite = "nc-musicblock-module-test.\(UUID().uuidString)"
    let preferences: NotchcastPreferences
    let presenter = NoticePresenter()
    let module: MusicBlockModule
    var running: Set<String> = ["com.spotify.client"]
    var played: [String] = []
    var outcome = LastPlayer.Outcome.played
    var settingsOpened = 0
    private let system = FakeSystem()
    private let subscriptions: Subscriptions
    private let deliver: (NotchcastTapEvent) -> Void
    private var pid: pid_t = 200

    init() {
        defaults = UserDefaults(suiteName: suite)!
        preferences = NotchcastPreferences(defaults: defaults, switches: MusicBlockAddon.switches)
        subscriptions = Subscriptions(system.makeHub())
        let context = NotchcastContext(
            defaults: defaults, preferences: preferences, presenter: presenter, hub: subscriptions.hub,
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { .now }, onTapsChanged: {})
        weak var rig: ResumeRig?
        module = MusicBlockModule(
            context: context, gestureAge: { .infinity }, isMusicRunning: { false },
            processID: { rig?.running.contains($0) == true ? 4242 : nil },
            play: { player, pid in
                precondition(pid == 4242, "sent to the running process, never by bundle id")
                rig?.played.append(player.bundleID)
                return rig?.outcome ?? .failed
            },
            openAutomationSettings: { rig?.settingsOpened += 1 })
        module.start()
        let tap = context.wantedTaps[0].tap
        subscriptions.add(tap)
        guard case .observe(let deliver) = tap.handler else { preconditionFailure("observed") }
        self.deliver = deliver
        rig = self
    }

    func close() {
        module.stop()
        defaults.removePersistentDomain(forName: suite)
    }

    /// Whether Music was stopped; any resume it started has finished on return.
    func pressThenLaunch(_ code: Int = 16) async -> Bool {
        let ns = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: code << 16 | 0x0A << 8, data2: -1)!
        let event = ns.cgEvent!
        event.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        deliver(NotchcastTapEvent(type: event.type, event: event, syntheticTag: syntheticTag))
        pid += 1
        let music = FakeMusic(pid)
        module.launched(music)
        await module.resuming?.value
        return music.stopped
    }
}

extension MusicBlockModuleTests {
    @MainActor
    static func resume() async {
        let rig = ResumeRig()
        defer { rig.close() }
        let module = rig.module
        var stopped: Bool

        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.isEmpty, "no player heard yet: Music is stopped, nothing plays")
        module.heard("com.spotify.client.PlaybackStateChanged", state: "Paused")
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.isEmpty, "a pause names no player")
        module.heard("com.spotify.client.PlaybackStateChanged", state: "Playing")
        precondition(rig.defaults.string(forKey: LastPlayer.storeKey) == "com.spotify.client", "remembered across runs")
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played == ["com.spotify.client"],
                     "play resumes Spotify in Music's place")
        stopped = await rig.pressThenLaunch(17)
        precondition(stopped && rig.played.count == 1, "next blocks Music but resumes nothing")
        rig.running = []
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.count == 1, "a quit player is never launched")
        rig.running = ["com.spotify.client"]
        rig.preferences.set("musicBlockResumeLastPlayer", on: false)
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.count == 1, "the option off leaves only the block")
        rig.preferences.set("musicBlockResumeLastPlayer", on: true)
        module.heard("com.apple.Music.playerInfo", state: "Playing")
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.count == 1, "Music played last: it is blocked, never resumed")
        precondition(rig.presenter.posts.isEmpty, "a resume that plays posts nothing")
    }

    @MainActor
    static func resumeFailures() async {
        let rig = ResumeRig()
        defer { rig.close() }
        rig.module.heard("com.spotify.client.PlaybackStateChanged", state: "Playing")
        var stopped: Bool

        rig.outcome = .refused
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.count == 1)
        guard let refusal = rig.presenter.posts.last else { preconditionFailure("a refusal is told") }
        precondition(refusal.notice.text == "Allow Automation access for Spotify." && refusal.notice.isFailure,
                     "a refusal names the fix, not a vague failure")
        guard let tap = refusal.onTap else { preconditionFailure("a refusal opens Automation settings on tap") }
        tap()
        precondition(rig.settingsOpened == 1)

        rig.outcome = .failed
        stopped = await rig.pressThenLaunch()
        precondition(stopped && rig.played.count == 2)
        guard let failure = rig.presenter.posts.last else { preconditionFailure("a failure is told") }
        precondition(failure.notice.text == "Couldn't resume Spotify." && failure.notice.isFailure)
        precondition(failure.onTap == nil, "only a refusal has a fix to open")
        precondition(rig.presenter.posts.count == 2, "one notice per press")
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
private final class NoticePresenter: IslandPresenting {
    private(set) var posts: [(notice: IslandNotice, onTap: (@MainActor () -> Void)?)] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append((notice, onTap)) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
private final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { preconditionFailure("no notice: \(notice.text)") }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
