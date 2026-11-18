// notchcast-sources: Tinycast/Features/Notchcast/Spotify/SpotifyAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Commands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Web.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifySystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyWeb.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import SwiftUI

// The shipped `live` system and settings view are left out: these stand in, so `makeModule` runs as shipped.
struct SpotifySettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

extension SpotifySystem {
    static var live: SpotifySystem { FakeSpotify.shared.system }
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Spotify-module-test: \(message)") }
}

/// Stands in for Soloist, the Keychain, the clock, Now Playing and Spotify's servers; nothing real runs.
@MainActor
final class FakeSpotify {
    static var shared = FakeSpotify()

    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var key: String? = "abcdefghij0123456789"
    var tokens: SpotifyTokens?
    var build = SoloistBuild(versionOutput: "soloist 1.3 build 1 (20270101)")
    var launches = 0
    var stops = 0
    var launchFails = false
    var exited: (@MainActor (SoloistExit) -> Void)?
    var rejected: (@MainActor () -> Void)?
    var event: (@MainActor (SoloistEvent) -> Void)?
    var closed: (@MainActor () -> Void)?
    var sent: [SoloistCommand] = []
    var wakes: [(date: Date, fire: @MainActor () -> Void)] = []
    var nowPlaying: [String] = []
    var remote: (@MainActor (SpotifyRemoteCommand) -> Void)?
    var requests: [String] = []
    var answers: [(Int, String)] = []
    var opened: [URL] = []

    var system: SpotifySystem {
        SpotifySystem(
            now: { [self] in now },
            soloistKey: { [self] in key },
            setSoloistKey: { [self] in key = $0 },
            tokens: { [self] in tokens },
            setTokens: { [self] in tokens = $0 },
            installedBuild: { [self] in build },
            install: { [self] in
                build = SoloistBuild(versionOutput: "soloist 1.4 build 1 (20270301)")
                return build!
            },
            launch: { [self] _, exited, rejected in
                launches += 1
                if launchFails { throw SoloistLaunchError.noSocket }
                self.exited = exited
                self.rejected = rejected
                return SoloistInstance(url: URL(string: "ws://127.0.0.1:1")!, stop: { [self] in stops += 1 })
            },
            connect: { [self] _, event, closed in
                self.event = event
                self.closed = closed
                return SoloistLink(send: { [self] in sent.append($0) }, close: {})
            },
            wake: { [self] date, fire in
                wakes.append((date, fire))
                return {}
            },
            nowPlaying: SpotifyNowPlayingSink(
                update: { [self] playback, _ in nowPlaying.append(playback?.track?.title ?? "none") },
                commands: { [self] in remote = $0 }),
            web: SpotifyWebTransport(
                send: { request in
                    let (status, body) = await MainActor.run {
                        FakeSpotify.shared.requests.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
                        return FakeSpotify.shared.answers.isEmpty ? (200, "[]") : FakeSpotify.shared.answers.removeFirst()
                    }
                    return .init(status: status, body: Data(body.utf8), retryAfter: nil)
                },
                awaitRedirect: { _, _ in
                    let url = await MainActor.run { FakeSpotify.shared.opened.last }
                    let state = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                        .queryItems?.first { $0.name == "state" }?.value ?? ""
                    return ["code": "C", "state": state]
                }),
            openURL: { [self] in opened.append($0) })
    }
}

/// Lets the module's tasks run; the fakes answer at once, so a few turns of the main actor suffice.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

let trackJSON = #"{"uri":"spotify:track:1","decorations":{"identity":{"name":"Paper Lanterns"},"creators":[{"entity":{"decorations":{"identity":{"name":"Juno Vale"}}}}],"playback":{"duration_ms":200000}}}"#

func event(_ json: String) -> SoloistEvent {
    guard let event = try? SoloistEvent.decode(Data(json.utf8)) else { fatalError("undecodable fixture") }
    return event
}

@main
struct SpotifyModuleTests {
    @MainActor
    static func main() async {
        check(SpotifyAddon.switches.map(\.id) == ["spotify"], "the switch id is frozen")
        check(SpotifyAddon.switches[0].defaultEnabled == false && SpotifyAddon.switches[0].category == .music, "off")
        await lifecycle()
        await restarts()
        await expiry()
        await web()
        print("Spotify module: Soloist supervised, volume restored, expiry warned once, library signed in")
    }

    @MainActor
    static func make(_ fake: FakeSpotify, defaults: UserDefaults) -> (SpotifyModule, RecordingPresenter) {
        FakeSpotify.shared = fake
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") }
        let presenter = RecordingPresenter()
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: SpotifyAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { fake.now }, onTapsChanged: {})
        guard let module = SpotifyAddon.makeModule(context) as? SpotifyModule else { preconditionFailure("module") }
        return (module, presenter)
    }

    @MainActor
    static func scratch() -> UserDefaults {
        let suite = "nc-spotify-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    static func lifecycle() async {
        let fake = FakeSpotify()
        let defaults = scratch()
        defaults.set(30, forKey: SpotifyModule.volumeKey)
        let (module, _) = make(fake, defaults: defaults)
        module.start()
        await settle()
        check(fake.launches == 1 && module.phase == .running, "the add-on on starts Soloist")
        check(fake.sent == [.getState, .setVolume(30)], "the saved volume is set again on start (D19)")
        fake.event?(event(#"{"type":"volume_changed","volume":100}"#))
        check(defaults.integer(forKey: SpotifyModule.volumeKey) == 30, "Soloist's own start level is not saved")
        fake.event?(event(#"{"type":"command_result","command":"set_volume"}"#))
        fake.event?(event(#"{"type":"volume_changed","volume":64}"#))
        check(defaults.integer(forKey: SpotifyModule.volumeKey) == 64, "a later change is the user's")
        fake.event?(event(#"{"type":"playback_state","status":"playing","item":\#(trackJSON),"is_active":false}"#))
        check(module.playback.track?.title == "Paper Lanterns" && fake.nowPlaying.last == "Paper Lanterns", "Now Playing")
        fake.sent = []
        fake.remote?(.next)
        await settle()
        check(fake.sent == [.activate, .skipNext], "another device plays: a press takes playback back first")
        fake.sent = []
        module.setVolume(20)
        await settle()
        check(fake.sent == [.setVolume(20)] && defaults.integer(forKey: SpotifyModule.volumeKey) == 20, "slider")
        module.seek(toMs: 999_999)
        check(module.playback.position.positionMs == 200_000, "a seek stops at the song's end")
        module.stop()
        await settle()
        check(fake.stops == 1 && fake.nowPlaying.last == "none" && fake.remote == nil, "off stops Soloist")
        check(module.playback == SpotifyPlayback(), "and forgets the song")
        let wakes = fake.wakes.count
        fake.exited?(.exited(1))
        check(fake.wakes.count == wakes && module.phase == .stopped, "a stopped module ignores a late exit")
    }

    @MainActor
    static func restarts() async {
        let fake = FakeSpotify()
        let (module, presenter) = make(fake, defaults: scratch())
        module.start()
        await settle()
        fake.exited?(.killed(9))
        await settle()
        check(fake.stops == 1, "a crashed Soloist is cleaned up")
        guard case .waiting(let at, 1) = module.phase else { return check(false, "waits to restart") }
        check(at == fake.now.addingTimeInterval(1) && fake.wakes.last?.date == at, "after one second")
        fake.now = at
        fake.wakes.removeLast().fire()
        await settle()
        check(fake.launches == 2 && module.phase == .running, "then starts again")
        fake.closed?()
        await settle()
        check(fake.stops == 2 && fake.wakes.last?.date == fake.now.addingTimeInterval(2), "a dropped socket backs off")
        fake.launchFails = true
        fake.now = fake.wakes.last!.date
        fake.wakes.removeLast().fire()
        await settle()
        check(fake.launches == 3 && fake.wakes.last?.date == fake.now.addingTimeInterval(4), "a failed launch too")
        fake.launchFails = false
        fake.now = fake.wakes.last!.date
        fake.wakes.removeLast().fire()
        await settle()
        fake.rejected?()
        check(module.phase == .keyRejected, "a refused key")
        check(presenter.log.last == "post spotify.failure Spotify Refused the Soloist Key", "says so in the island")
        fake.exited?(.expired)
        check(module.phase == .keyRejected, "a rejected key is not retried")
        module.removeKey()
        check(module.phase == .needsKey && !module.hasKey && fake.key == nil, "removing the key stops Soloist")
        do { try module.setKey("bad key") } catch { check(error == .whitespace, "a pasted slip is refused") }
        try? module.setKey("abcdefghij0123456789")
        await settle()
        check(module.phase == .running && fake.launches == 5, "a new key starts it")
        fake.exited?(.expired)
        check(module.phase == .expired && presenter.log.last == "post spotify.failure Soloist Expired", "expired")
        await module.install()
        await settle()
        check(module.build?.version == "1.4" && module.phase == .running, "an update installs and starts again")
        module.stop()
    }

    @MainActor
    static func expiry() async {
        let fake = FakeSpotify()
        let defaults = scratch()
        let build = fake.build!
        fake.now = build.noticeDate.addingTimeInterval(-60)
        let (module, presenter) = make(fake, defaults: defaults)
        module.start()
        await settle()
        check(!presenter.log.contains { $0.hasPrefix("post spotify.expiry") }, "quiet before the last week")
        guard let wake = fake.wakes.first(where: { $0.date == build.noticeDate }) else { return check(false, "wakes") }
        fake.now = build.noticeDate
        wake.fire()
        check(presenter.log.last == "post spotify.expiry Soloist stops working in 7 days. Update it in Settings.",
              "one warning a week before (D10)")
        module.stop()
        module.start()
        await settle()
        check(presenter.log.filter { $0.hasPrefix("post spotify.expiry") }.count == 1, "once per build")
        module.stop()
    }

    @MainActor
    static func web() async {
        let fake = FakeSpotify()
        let (module, _) = make(fake, defaults: scratch())
        module.start()
        await settle()
        check(module.web == nil && !module.isSignedIn, "no client id, no library")
        module.setClientID("  client  ")
        check(module.clientID == "client" && module.web != nil, "BYOK client id")
        fake.answers = [(200, #"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#)]
        await module.signIn()
        check(module.isSignedIn && fake.tokens?.refreshToken == "R", "tokens land in the Keychain")
        check(fake.opened.last?.host() == "accounts.spotify.com", "the browser opens Spotify's sign-in")
        fake.event?(event(#"{"type":"playback_state","status":"playing","item":\#(trackJSON),"is_active":true}"#))
        fake.answers = [(200, "[true]")]
        module.refreshLiked()
        await settle()
        check(module.liked == true && fake.requests.last == "GET /v1/me/library/contains", "liked state")
        fake.answers = [(500, "")]
        module.toggleLike()
        check(module.liked == false, "the heart answers at once")
        await settle()
        check(module.liked == true && fake.requests.last == "DELETE /v1/me/library", "and returns when Spotify fails")
        fake.answers = [(401, ""), (400, #"{"error":"invalid_grant"}"#)]
        module.refreshLiked()
        await settle()
        check(!module.isSignedIn && fake.tokens == nil && module.liked == nil, "a revoked sign-in signs out")
        module.setClientID("other")
        check(fake.tokens == nil, "a new client id drops the old tokens")
        module.stop()
    }
}
