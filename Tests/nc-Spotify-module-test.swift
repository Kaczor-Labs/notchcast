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
// notchcast-sources: Tinycast/Features/Island/Service/IslandPlayerSource.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyPlayerPage.swift
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
    /// Bind, open, cancel and redirect steps of each sign-in, in order.
    var signInLog: [String] = []
    var launchHangs = false
    var launchCancelled = false
    var hang: CheckedContinuation<Void, any Error>?
    var redirectHangs = false
    var redirectCancelled = false
    var pendingRedirect: CheckedContinuation<[String: String], any Error>?

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
            launch: { [self] _, spawned, exited, rejected in
                launches += 1
                if launchFails { throw SoloistLaunchError.noSocket }
                self.exited = exited
                self.rejected = rejected
                spawned { [self] in stops += 1 }
                if launchHangs {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { hang = $0 }
                    } onCancel: {
                        Task { @MainActor in
                            FakeSpotify.shared.launchCancelled = true
                            FakeSpotify.shared.hang?.resume(throwing: CancellationError())
                        }
                    }
                }
                return URL(string: "ws://127.0.0.1:1")!
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
                listen: { _, _, state in
                    await MainActor.run { FakeSpotify.shared.signInLog.append("bound") }
                    return SpotifyRedirectListener(
                        redirect: { @MainActor in
                            let fake = FakeSpotify.shared
                            guard fake.redirectHangs else { return ["code": "C", "state": state] }
                            return try await withTaskCancellationHandler {
                                try await withCheckedThrowingContinuation { fake.pendingRedirect = $0 }
                            } onCancel: {
                                Task { @MainActor in
                                    FakeSpotify.shared.redirectCancelled = true
                                    FakeSpotify.shared.pendingRedirect?.resume(throwing: SpotifyAuthError.cancelled)
                                    FakeSpotify.shared.pendingRedirect = nil
                                }
                            }
                        },
                        cancel: { MainActor.assumeIsolated { FakeSpotify.shared.signInLog.append("cancel") } })
                }),
            openURL: { [self] in
                opened.append($0)
                signInLog.append("open")
            })
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
        await player()
        await ownership()
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

    /// Records the Player page the add-on posts, so the island's view of Spotify is checked as shipped.
    @MainActor
    final class PagePresenter: IslandPresenting {
        var page: IslandPage?
        var action: (@MainActor (String) -> Void)?
        func showLevel(_ level: IslandLevel) {}
        func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
        func end(notice id: String) {}
        func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
        func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
        func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
            check(id == "player", "Spotify posts only the Player page")
            self.page = page
            action = onAction
        }
    }

    @MainActor
    static func player() async {
        let fake = FakeSpotify()
        FakeSpotify.shared = fake
        let defaults = scratch()
        let presenter = PagePresenter()
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: SpotifyAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { fake.now }, onTapsChanged: {})
        guard let module = SpotifyAddon.makeModule(context) as? SpotifyModule else { return check(false, "module") }
        module.start()
        await settle()
        check(presenter.page == nil, "no song, no Player page")
        let cover = #""visual_identity":{"cover":[{"url":"https://covers.test/a.jpg","size":"large"}]},"#
        let track = trackJSON.replacingOccurrences(of: #""playback":"#, with: cover + #""playback":"#)
        fake.answers = [(200, "JPEG")]
        fake.event?(event(#"{"type":"playback_state","status":"paused","item":\#(track),"is_active":true,"#
            + #""position":{"position_ms":30000,"timestamp_ms":1000,"speed":0}}"#))
        await settle()
        guard case .media(let media)? = presenter.page?.blocks.first else { return check(false, "a Player page") }
        check(media.title == "Paper Lanterns" && media.subtitle == "Juno Vale", "the song and its artist")
        let sampled = Date(timeIntervalSince1970: 1)
        check(media.time == IslandMediaTime(elapsed: 30, duration: 200, rate: 0, sampledAt: sampled),
              "the time runs from Soloist's position, paused")
        check(media.buttons.map(\.symbol) == ["backward.fill", "play.fill", "forward.fill"], "paused shows Play")
        check(fake.requests == ["GET /a.jpg"] && media.artwork == Data("JPEG".utf8), "the cover, fetched once")
        fake.event?(event(#"{"type":"position_sync","position":{"position_ms":31000,"timestamp_ms":2000,"speed":0}}"#))
        await settle()
        check(fake.requests.count == 1 && presenter.page?.line.artwork == Data("JPEG".utf8), "and kept per song")
        fake.sent = []
        presenter.action?(IslandPlayerControl.next.rawValue)
        presenter.action?(IslandPlayerControl.playPause.rawValue)
        presenter.action?(IslandPage.refreshAction)
        await settle()
        check(fake.sent == [.skipNext, .play(uri: nil), .getState], "the page's buttons and Command-R reach Soloist")
        module.stop()
        await settle()
        check(presenter.page == nil, "off removes the Player page")
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

    /// Off, quit, a new client id and a second sign-in each end what is still in flight.
    @MainActor
    static func ownership() async {
        let fake = FakeSpotify()
        fake.launchHangs = true
        let (module, _) = make(fake, defaults: scratch())
        module.start()
        await settle()
        check(fake.launches == 1 && module.phase == .starting, "Soloist spawned, its socket not up yet")
        module.stop()
        check(fake.stops == 1, "off stops a Soloist still starting, at once, as quit does")
        await settle()
        check(fake.launchCancelled, "and cancels its launch")
        fake.launchHangs = false
        module.start()
        await settle()
        check(fake.launches == 2 && module.phase == .running && fake.stops == 1, "on again starts a fresh one")

        module.setClientID("client")
        fake.redirectHangs = true
        Task { await module.signIn() }
        await settle()
        check(fake.signInLog == ["bound", "open"], "the redirect port listens before the browser opens")
        module.stop()
        await settle()
        check(fake.redirectCancelled && !module.signingIn && fake.signInLog.last == "cancel", "off ends the sign-in")

        module.start()
        await settle()
        fake.redirectCancelled = false
        fake.signInLog = []
        Task { await module.signIn() }
        await settle()
        fake.redirectHangs = false
        fake.answers = [(200, #"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#)]
        await module.signIn()
        check(fake.redirectCancelled, "a second sign-in ends the first")
        check(fake.signInLog == ["bound", "open", "cancel", "bound", "open", "cancel"], "and frees the port first")
        check(module.isSignedIn && !module.signingIn && fake.tokens?.refreshToken == "R", "then signs in")

        fake.redirectHangs = true
        fake.redirectCancelled = false
        Task { await module.signIn() }
        await settle()
        module.setClientID("other")
        await settle()
        check(fake.redirectCancelled && !module.signingIn, "a new client id ends the sign-in in flight")

        module.setClientID("client")
        fake.tokens = SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: fake.now, scope: "")
        module.rebuildWeb()
        guard let old = module.web else { return check(false, "signed in") }
        module.setClientID("third")
        fake.answers = [(200, #"{"access_token":"B","expires_in":3600,"refresh_token":"R2"}"#), (200, "[true]")]
        _ = try? await old.isSaved("spotify:track:1")
        check(fake.tokens == nil && !module.isSignedIn, "the old id's refresh never lands under the new id")
        module.stop()
    }
}
