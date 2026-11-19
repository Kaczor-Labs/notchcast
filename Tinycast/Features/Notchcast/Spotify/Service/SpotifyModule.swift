import Foundation
import Observation

/// Keeps Soloist running while the add-on is on and mirrors its playback for the island and Now Playing.
@MainActor
@Observable
final class SpotifyModule: NotchcastModule {
    static let volumeKey = "spotifyVolume"
    static let noticedBuildKey = "spotifyNoticedBuild"
    static let clientIDKey = "spotifyClientID"
    static let expiryNoticeID = "spotify.expiry"
    static let failureNoticeID = "spotify.failure"

    @ObservationIgnored let context: NotchcastContext
    @ObservationIgnored let system: SpotifySystem
    private(set) var playback = SpotifyPlayback()
    private(set) var supervision = SoloistSupervision()
    private(set) var build: SoloistBuild?
    private(set) var hasKey = false
    private(set) var installing = false
    private(set) var installError: SoloistInstallError?
    var signInError: SpotifyAuthError?
    var signingIn = false
    var isSignedIn = false
    var clientID: String
    /// Whether the current song is in Liked Songs; nil while unknown or signed out.
    var liked: Bool?
    @ObservationIgnored var web: SpotifyWeb?
    @ObservationIgnored private var volume: SpotifyVolumeMemory
    /// Set the moment Soloist is spawned or adopted, so stop and quit never leave it running.
    @ObservationIgnored private var stopSoloist: (@MainActor () -> Void)?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored var signInTask: Task<Void, any Error>?
    @ObservationIgnored private(set) var link: SoloistLink?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cancelRetry: (@MainActor () -> Void)?
    @ObservationIgnored private var cancelNotice: (@MainActor () -> Void)?
    @ObservationIgnored private(set) var running = false
    /// Called after every playback change, before Now Playing; the island player hooks in here.
    @ObservationIgnored var onPlayback: (@MainActor (_ old: SpotifyPlayback, _ new: SpotifyPlayback) -> Void)?

    init(context: NotchcastContext, system: SpotifySystem) {
        self.context = context
        self.system = system
        volume = SpotifyVolumeMemory(saved: context.defaults.object(forKey: Self.volumeKey) as? Int)
        clientID = context.defaults.string(forKey: Self.clientIDKey) ?? ""
    }

    var phase: SoloistPhase { supervision.phase }
    var savedVolume: Int { volume.saved }
    var now: Date { system.now() }

    func start() {
        guard !running else { return }
        running = true
        generation += 1
        let token = generation
        hasKey = system.soloistKey() != nil
        rebuildWeb()
        system.nowPlaying.commands { [weak self] in self?.remote($0) }
        Task {
            let build = await system.installedBuild()
            guard token == generation, running else { return }
            self.build = build
            supervise()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        cancelSignIn()
        halt()
        supervision.stop()
        cancelNotice?()
        cancelNotice = nil
        system.nowPlaying.commands(nil)
        system.nowPlaying.update(nil, 0)
        context.presenter.end(notice: Self.expiryNoticeID)
        context.presenter.end(notice: Self.failureNoticeID)
        apply(SpotifyPlayback())
    }

    /// Stops the current Soloist without touching the supervision phase; later callbacks are ignored.
    private func halt() {
        generation += 1
        cancelRetry?()
        cancelRetry = nil
        launchTask?.cancel()
        launchTask = nil
        link?.close()
        link = nil
        stopSoloist?()
        stopSoloist = nil
    }

    func supervise() {
        guard running else { return }
        supervision.start(hasKey: hasKey, build: build, at: now)
        scheduleExpiryNotice()
        switch supervision.phase {
        case .starting: launch()
        case .expired: fail(String(localized: "Soloist Expired", table: "NotchcastSpotify"))
        default: break
        }
    }

    private func launch() {
        guard let key = system.soloistKey() else {
            hasKey = false
            return supervise()
        }
        generation += 1
        let token = generation
        let system = system
        let spawned: @MainActor (@escaping @MainActor () -> Void) -> Void = { [weak self] stop in
            guard let self, token == generation, running else { return stop() }
            stopSoloist = stop
        }
        launchTask = Task { [weak self] in
            do {
                let url = try await system.launch(key, spawned, { [weak self] in self?.exited($0, token) },
                                                  { [weak self] in self?.rejected(token) })
                guard let self, token == generation, running else { return }
                launchTask = nil
                supervision.launched(at: now)
                connect(url, token)
            } catch SoloistLaunchError.notInstalled {
                guard let self, token == generation else { return }
                build = nil
                supervise()
            } catch {
                guard let self, token == generation else { return }
                halt()
                retry(supervision.failed(at: now))
            }
        }
    }

    private func connect(_ url: URL, _ token: Int) {
        let link = system.connect(url, { [weak self] in self?.received($0, token) },
                                  { [weak self] in self?.closed(token) })
        self.link = link
        let level = volume.connected()
        Task {
            try? await link.send(.getState)
            try? await link.send(.setVolume(level))
        }
    }

    private func received(_ event: SoloistEvent, _ token: Int) {
        guard token == generation else { return }
        switch event {
        case .volumeChanged(let level): remember(level)
        case .playbackState(let state): if let level = state.volume { remember(level) }
        case .commandResult("set_volume"): volume.acknowledged()
        default: break
        }
        apply(playback.applying(event))
    }

    func storeVolume(_ level: Int) -> Int {
        let value = volume.set(level)
        context.defaults.set(value, forKey: Self.volumeKey)
        return value
    }

    private func remember(_ level: Int) {
        if volume.reported(level) { context.defaults.set(level, forKey: Self.volumeKey) }
    }

    func apply(_ next: SpotifyPlayback) {
        let old = playback
        guard next != old else { return }
        playback = next
        onPlayback?(old, next)
        let elapsed = Double(next.position.current(at: now, durationMs: next.track?.durationMs)) / 1000
        system.nowPlaying.update(next.track == nil ? nil : next, elapsed)
    }

    /// A dropped socket means Soloist is gone or wedged: stop it and start over with back-off.
    private func closed(_ token: Int) {
        guard token == generation else { return }
        halt()
        retry(supervision.failed(at: now))
    }

    private func exited(_ exit: SoloistExit, _ token: Int) {
        guard token == generation else { return }
        halt()
        var paused = playback
        paused.status = .paused
        paused.position.speed = 0
        apply(paused)
        retry(supervision.ended(exit, at: now))
        if supervision.phase == .expired { fail(String(localized: "Soloist Expired", table: "NotchcastSpotify")) }
    }

    private func rejected(_ token: Int) {
        guard token == generation else { return }
        supervision.rejected()
        fail(String(localized: "Spotify Refused the Soloist Key", table: "NotchcastSpotify"))
    }

    private func retry(_ date: Date?) {
        guard let date else { return }
        cancelRetry?()
        cancelRetry = system.wake(date) { [weak self] in
            guard let self, self.supervision.retryDue(at: self.now) else { return }
            self.launch()
        }
    }

    /// The shipped failure notice, 4 s, red glyph (design 1d).
    func fail(_ text: String) {
        context.presenter.post(IslandNotice(id: Self.failureNoticeID, symbol: "exclamationmark.triangle.fill",
                                            text: text, isFailure: true), onTap: nil)
    }

    /// One warning per build, a week before it stops (decision D10); a later build warns again.
    private func scheduleExpiryNotice() {
        cancelNotice?()
        cancelNotice = nil
        guard let build, !build.isExpired(at: now),
              context.defaults.string(forKey: Self.noticedBuildKey) != build.version else { return }
        guard build.expiresSoon(at: now) else {
            cancelNotice = system.wake(build.noticeDate) { [weak self] in self?.scheduleExpiryNotice() }
            return
        }
        context.defaults.set(build.version, forKey: Self.noticedBuildKey)
        let days = build.daysLeft(at: now)
        let text = days == 1
            ? String(localized: "Soloist stops working tomorrow. Update it in Settings.", table: "NotchcastSpotify")
            : String(localized: "Soloist stops working in \(days) days. Update it in Settings.", table: "NotchcastSpotify")
        context.presenter.post(IslandNotice(id: Self.expiryNoticeID, symbol: "clock.badge.exclamationmark",
                                            text: text, seconds: IslandNotice.failureSeconds), onTap: nil)
    }

    // MARK: - Setup

    func setKey(_ input: String) throws(SoloistKey.Problem) {
        let key = try SoloistKey.normalize(input)
        system.setSoloistKey(key)
        hasKey = true
        restart()
    }

    func removeKey() {
        system.setSoloistKey(nil)
        hasKey = false
        restart()
    }

    func restart() {
        guard running else { return }
        halt()
        supervision.stop()
        supervise()
    }

    /// Stops Soloist, installs Spotify's current build and starts it again.
    func install() async {
        guard running, !installing else { return }
        installing = true
        installError = nil
        halt()
        supervision.updating()
        do {
            build = try await system.install()
        } catch let error as SoloistInstallError {
            installError = error
        } catch {
            installError = .install
        }
        installing = false
        guard running else { return }
        supervision.stop()
        supervise()
    }
}
