// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Spotify-model-test: \(message)") }
}

func event(_ json: String) -> SoloistEvent {
    guard let decoded = try? SoloistEvent.decode(Data(json.utf8)) else { fatalError("undecodable \(json)") }
    return decoded
}

let trackJSON = """
{"uri":"spotify:track:1","entity_type":"track","decorations":{"identity":{"name":"Paper Lanterns"},
"visual_identity":{"cover":[{"url":"https://i/s","size":"small"},{"url":"https://i/l","size":"large"}]},
"parent":{"entity":{"uri":"spotify:album:9","decorations":{"identity":{"name":"Harbour"}}}},
"creators":[{"entity":{"uri":"spotify:artist:2","decorations":{"identity":{"name":"Juno Vale"}}}}],
"playback":{"duration_ms":200000}}}
"""

/// Soloist's wire format, state mapping, build expiry, supervision, volume memory, PKCE and Web API mapping.
@main
enum SpotifyModelTests {
    static func main() {
        commands()
        events()
        position()
        build()
        key()
        supervision()
        volume()
        pkce()
        web()
        launchRules()
        redirect()
        print("Spotify model: wire, state, expiry, back-off, volume, PKCE and Web API mapping hold")
    }

    static func commands() {
        check(SoloistCommand.seek(positionMs: 5).encoded() == #"{"command":"seek","position_ms":5,"type":"command"}"#,
              "seek encodes its position")
        check(SoloistCommand.setVolume(140).encoded().contains(#""volume":100"#), "volume clamps to 100")
        check(!SoloistCommand.play(uri: nil).encoded().contains("uri"), "a resume sends no uri")
        check(SoloistCommand.skipPrevious.name == "skip_prev", "Soloist's own name")
    }

    static func events() {
        let state = event(#"{"type":"playback_state","status":"playing","item":\#(trackJSON),"position":{"position_ms":1000,"timestamp_ms":0,"speed":1},"volume":40,"is_active":true,"context":{"uri":"spotify:playlist:7","entity_type":"playlist","decorations":{"identity":{"name":"Focus"}}},"available_actions":{"pause":{},"skip_next":{},"seek_forward":{"step_ms":15000}}}"#)
        let playback = SpotifyPlayback().applying(state)
        check(playback.status == .playing && playback.isPlaying, "status maps")
        check(playback.track?.title == "Paper Lanterns" && playback.track?.artistLine == "Juno Vale", "title, artist")
        check(playback.track?.album == "Harbour" && playback.track?.durationMs == 200_000, "album, duration")
        check(playback.track?.artworkURL?.absoluteString == "https://i/l", "the large cover for the player")
        check(playback.track?.thumbnailURL?.absoluteString == "https://i/s", "the small cover for rows")
        check(playback.volume == 40 && playback.isActiveDevice && playback.contextName == "Focus", "volume, device")
        check(playback.actions == [.pause, .skipNext], "unknown actions are dropped")
        let paused = playback.applying(event(#"{"type":"playback_changed","status":"paused"}"#))
        check(paused.status == .paused && paused.track == playback.track, "a status change keeps the song")
        check(playback.applying(event(#"{"type":"volume_changed","volume":7}"#)).volume == 7, "volume event")
        check(playback.applying(event(#"{"type":"track_changed","item":null}"#)).track == nil, "nothing loaded")
        check(playback.applying(event(#"{"type":"something_new","x":1}"#)) == playback, "unknown types are ignored")
        let queued = playback.applying(event(#"{"type":"queue_changed","upcoming":[{"uid":"a","source":"queue","item":\#(trackJSON)},{"source":"autoplay","item":{"uri":"spotify:episode:1","decorations":{"identity":{"name":"Talk"}}}}]}"#))
        check(queued.upNext.map(\.id) == ["a"] && queued.upNext.first?.source == .queue, "episodes are left out")
        let auth = SpotifyPlayback().applying(event(#"{"type":"auth_state","logged_in":true,"is_active":false}"#))
        check(auth.isLoggedIn && !auth.isActiveDevice, "auth state")
        check(event(#"{"type":"command_result","command":"set_volume"}"#) == .commandResult(command: "set_volume"),
              "command results")
        check((try? SoloistEvent.decode(Data("nope".utf8))) == nil, "garbage throws, the socket skips it")
    }

    static func position() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let moving = SpotifyPosition(positionMs: 10_000, timestamp: anchor, speed: 1)
        check(moving.current(at: anchor.addingTimeInterval(2.5), durationMs: 60_000) == 12_500, "advances with time")
        check(moving.current(at: anchor.addingTimeInterval(120), durationMs: 60_000) == 60_000, "stops at the end")
        let still = SpotifyPosition(positionMs: 10_000, timestamp: anchor, speed: 0)
        check(still.current(at: anchor.addingTimeInterval(30), durationMs: nil) == 10_000, "paused stays put")
        let sync = SpotifyPosition(soloist: SoloistWire.Position(positionMs: 5, timestampMs: 2_000, speed: 1))
        check(sync.timestamp == Date(timeIntervalSince1970: 2), "epoch milliseconds")
    }

    static func build() {
        guard let build = SoloistBuild(versionOutput: "soloist 1.3.10.65 build 1794463304 (20261112) (g19412df6ea) (macos/aarch64)")
        else { return check(false, "the version line parses") }
        check(build.version == "1.3.10.65", "version")
        let day = Date(timeIntervalSince1970: 1_794_441_600)
        check(build.buildDate == day, "the build day, UTC")
        check(build.expiryDate == day.addingTimeInterval(90 * 86_400), "90 days")
        check(!build.expiresSoon(at: day.addingTimeInterval(82 * 86_400)), "quiet until the last week")
        check(build.expiresSoon(at: day.addingTimeInterval(83 * 86_400)), "the notice week")
        check(build.daysLeft(at: day.addingTimeInterval(89.5 * 86_400)) == 1, "the last day reads one")
        check(build.isExpired(at: build.expiryDate) && !build.isExpired(at: build.noticeDate), "expiry instant")
        check(SoloistBuild(versionOutput: "soloist dev") == nil, "an unknown format")
        check(SoloistExit(status: 10, signalled: false) == .expired, "exit 10 is an expired build")
        check(SoloistExit(status: 9, signalled: true) == .killed(9), "a signal is not an exit code")
    }

    static func key() {
        check((try? SoloistKey.normalize("  abcDEF_0123456789-xyz \n")) == "abcDEF_0123456789-xyz", "trims")
        func problem(_ input: String) -> SoloistKey.Problem? {
            do { _ = try SoloistKey.normalize(input); return nil } catch { return error }
        }
        check(problem("") == .empty && problem("abc def 0123456789x") == .whitespace, "empty, spaces")
        check(problem("abcdefghij0123456789é") == .characters && problem("short") == .length, "characters, length")
        check(SoloistKey.isRejection("2026-11-12 13:36:58.812: login failed: make sure --api-key is valid"), "reject")
    }

    static func supervision() {
        let start = Date(timeIntervalSince1970: 0)
        guard let build = SoloistBuild(versionOutput: "soloist 1 build 1 (19700101)") else { return check(false, "b") }
        var s = SoloistSupervision()
        s.start(hasKey: false, build: build, at: start)
        check(s.phase == .needsKey, "a key comes first")
        s.start(hasKey: true, build: nil, at: start)
        check(s.phase == .notInstalled, "then an install")
        s.start(hasKey: true, build: build, at: start.addingTimeInterval(91 * 86_400))
        check(s.phase == .expired, "an expired build never launches")
        s.start(hasKey: true, build: build, at: start)
        s.launched(at: start)
        check(s.phase == .running, "running")
        let first = s.ended(.exited(1), at: start.addingTimeInterval(5))
        check(first == start.addingTimeInterval(6), "one second, then")
        check(!s.retryDue(at: start.addingTimeInterval(5.5)) && s.retryDue(at: start.addingTimeInterval(6)), "due")
        s.launched(at: start.addingTimeInterval(6))
        check(s.ended(.killed(9), at: start.addingTimeInterval(7)) == start.addingTimeInterval(9), "two seconds")
        _ = s.retryDue(at: start.addingTimeInterval(9))
        check(s.failed(at: start.addingTimeInterval(9)) == start.addingTimeInterval(13), "a failed launch backs off too")
        for _ in 0..<10 { _ = s.retryDue(at: .distantFuture); _ = s.failed(at: start) }
        if case .waiting(let at, _) = s.phase { check(at == start.addingTimeInterval(60), "capped at a minute") }
        _ = s.retryDue(at: .distantFuture)
        s.launched(at: start)
        check(s.ended(.exited(1), at: start.addingTimeInterval(61)) == start.addingTimeInterval(62), "a stable run resets")
        _ = s.retryDue(at: .distantFuture)
        s.launched(at: start)
        check(s.ended(.expired, at: start) == nil && s.phase == .expired, "expired is not retried")
        s.stop()
        check(s.ended(.exited(1), at: start) == nil && s.phase == .stopped, "a stopped one stays stopped")
        s.start(hasKey: true, build: build, at: start)
        s.rejected()
        check(s.phase == .keyRejected, "a rejected key")
    }

    static func volume() {
        var memory = SpotifyVolumeMemory(saved: 30)
        check(memory.connected() == 30, "restores the saved level on connect")
        check(!memory.reported(100) && memory.saved == 30, "Soloist's start-up level is not the user's")
        check(!memory.reported(30) && memory.restored, "the restored level confirms")
        check(memory.reported(45) && memory.saved == 45, "later changes are the user's")
        _ = memory.connected()
        memory.acknowledged()
        check(memory.reported(60) && memory.saved == 60, "an acknowledged set_volume confirms too")
        check(memory.set(130) == 100 && SpotifyVolumeMemory(saved: nil).saved == 50, "clamped, default 50")
    }

    static func pkce() {
        let rfc = SpotifyAuthorization(clientID: " abc ", verifier: "abc", state: "s1")
        check(rfc.challenge == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0", "base64url SHA-256, no padding")
        check(rfc.clientID == "abc", "the pasted id is trimmed")
        let query = URLComponents(url: rfc.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let items = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        check(items["redirect_uri"] == "http://127.0.0.1:43822/callback", "our own port")
        check(items["code_challenge_method"] == "S256" && items["state"] == "s1", "S256 and the state")
        check((try? rfc.code(from: ["state": "s1", "code": "c"])) == "c", "the code")
        func failure(_ query: [String: String]) -> SpotifyAuthError? {
            do { _ = try rfc.code(from: query); return nil } catch { return error }
        }
        check(failure(["state": "other", "code": "c"]) == .stateMismatch, "a foreign redirect")
        check(failure(["state": "s1", "error": "access_denied"]) == .cancelled, "the user cancelled")
        var generator = SystemRandomNumberGenerator()
        let fresh = SpotifyAuthorization.begin(clientID: "x", using: &generator)
        check(fresh.verifier.count == 64 && fresh.state.count == 32, "verifier and state lengths")
        check(SpotifyAuthorization.formEncode(["b": "a b", "a": "x/y"]) == "a=x%2Fy&b=a%20b", "sorted, encoded")
        let now = Date(timeIntervalSince1970: 100)
        let body = Data(#"{"access_token":"A","expires_in":3600,"refresh_token":"R","scope":"s"}"#.utf8)
        let tokens = try? SpotifyAuthorization.tokens(status: 200, body: body, previous: nil, now: now)
        check(tokens?.refreshToken == "R" && tokens?.expiresAt == now.addingTimeInterval(3600), "tokens")
        let refreshed = try? SpotifyAuthorization.tokens(
            status: 200, body: Data(#"{"access_token":"B","expires_in":60}"#.utf8), previous: tokens, now: now)
        check(refreshed?.refreshToken == "R" && refreshed?.scope == "s", "a refresh keeps the refresh token")
        check(refreshed?.needsRefresh(at: now) == true, "a minute early")
        do {
            _ = try SpotifyAuthorization.tokens(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8),
                                                previous: tokens, now: now)
            check(false, "invalid_grant throws")
        } catch { check(error == .signInAgain, "a revoked refresh asks to sign in again") }
        let redirect = SpotifyRedirect.parse("GET /callback?code=a%20b&state=s HTTP/1.1\r\nHost: x")
        check(redirect?.path == "/callback" && redirect?.query["code"] == "a b", "the redirect line")
    }

    static func web() {
        check(SpotifyWebOutcome(status: 204, retried: false, retryAfter: nil) == .ok, "2xx")
        check(SpotifyWebOutcome(status: 401, retried: false, retryAfter: nil) == .refresh, "401 refreshes once")
        check(SpotifyWebOutcome(status: 401, retried: true, retryAfter: nil) == .signInAgain, "then signs in again")
        check(SpotifyWebOutcome(status: 429, retried: false, retryAfter: " 30 ") == .rateLimited(seconds: 30), "429")
        check(SpotifyWebOutcome(status: 429, retried: false, retryAfter: nil) == .rateLimited(seconds: 2), "default")
        check(SpotifyWebOutcome(status: 503, retried: false, retryAfter: nil) == .retry, "a hiccup retries once")
        check(SpotifyWebOutcome(status: 503, retried: true, retryAfter: nil) == .failed(status: 503), "then fails")
        let json = #"{"items":[null,{"uri":"spotify:playlist:1","name":"Focus","owner":{"id":"u","display_name":"Me"},"items":{"total":12},"images":[{"url":"https://i/640","width":640},{"url":"https://i/60","width":60}]}],"offset":0,"next":"n"}"#
        let page = SpotifyWire.decode(SpotifyWire.Paging<SpotifyWire.Playlist>.self, Data(json.utf8))?.page(SpotifyWire.item)
        check(page?.items.count == 1 && page?.nextOffset == 2, "nulls skipped, next offset")
        check(page?.items.first?.count == 12 && page?.items.first?.subtitle == "Me", "count and owner")
        check(page?.items.first?.imageURL?.absoluteString == "https://i/60", "the small image for rows")
        let local = SpotifyWire.Track(uri: "spotify:local:x", name: "x", type: "track", artists: nil, album: nil,
                                      durationMs: 1, isLocal: true)
        check(SpotifyWire.item(local) == nil, "local files can't play")
    }

    static func launchRules() {
        typealias Rules = SoloistLaunchRules
        check(Rules.socketURL(port: "4321\n", address: "127.0.0.1\n")?.absoluteString == "ws://127.0.0.1:4321", "url")
        check(Rules.socketURL(port: "4321", address: nil) == nil, "a missing ws.addr is refused")
        check(Rules.socketURL(port: "4321", address: "0.0.0.0") == nil, "a non-loopback address is refused")
        check(Rules.socketURL(port: "70000", address: "127.0.0.1") == nil, "a port out of range")
        check(Rules.pid(" 42\n") == 42 && Rules.pid("0") == nil && Rules.pid(nil) == nil, "pid file")
        let installed = "/opt/notchcast/Soloist/soloist"
        check(Rules.adoptable(runningPath: installed, installedPath: installed, signed: true, stopping: false), "ours")
        check(!Rules.adoptable(runningPath: "/tmp/soloist", installedPath: installed, signed: true, stopping: false),
              "a look-alike named soloist elsewhere is not adopted")
        check(!Rules.adoptable(runningPath: installed, installedPath: installed, signed: false, stopping: false),
              "an unsigned process at our path is not adopted")
        check(!Rules.adoptable(runningPath: installed, installedPath: installed, signed: true, stopping: true),
              "a process being stopped is not adopted")
        check(!Rules.adoptable(runningPath: nil, installedPath: installed, signed: true, stopping: false), "gone")
    }

    static func redirect() {
        func decide(_ text: String, ended: Bool = false) -> SpotifyRedirectDecision {
            SpotifyRedirect.decide(Data(text.utf8), ended: ended, path: "/callback", state: "S")
        }
        let head = "GET /callback?code=C&state=S HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        check(decide(head) == .readMore, "a request head cut short waits for the rest")
        check(decide(head, ended: true) == .reply(status: 400), "and is dropped if the peer stops there")
        check(decide(head + "\r\n") == .finish(["code": "C", "state": "S"]), "the whole head ends the wait")
        check(decide("GET /callback?code=X&state=other HTTP/1.1\r\n\r\n") == .reply(status: 400),
              "another state is answered and ignored")
        check(decide("GET /favicon.ico HTTP/1.1\r\n\r\n") == .reply(status: 404), "another path")
        check(decide("GET /callback?error=access_denied&state=S HTTP/1.1\r\n\r\n")
              == .finish(["error": "access_denied", "state": "S"]), "a refusal with our state ends it too")
        check(decide(String(repeating: "a", count: SpotifyRedirect.maxRequestBytes + 1)) == .reply(status: 431),
              "an oversized request")
    }
}
