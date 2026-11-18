// notchcast-sources: Tinycast/Features/Notchcast/Spotify/SpotifyAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Commands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Web.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifySystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyWeb.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyIsland.swift
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
// notchcast-sources: Tinycast/Features/Island/Model/IslandMedia.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandMediaPresenting.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import Carbon.HIToolbox
import SwiftUI

// The shipped `live` system and views are left out: these stand in, so `makeModule` runs as shipped.
struct SpotifySettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct SpotifyIslandSettingsRow: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct SpotifyPlayerView: View {
    static let pageSize = CGSize(width: 718, height: 144)
    static let volumeStep = 5
    init(module: SpotifyModule) {}
    var body: some View { EmptyView() }
}

@MainActor
@Observable
final class SpotifyCovers {
    init(send: @escaping @Sendable (URLRequest) async throws -> SpotifyWebTransport.Response) {}
}

extension SpotifySystem {
    static var live: SpotifySystem { Fake.shared.system }
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Spotify-island-test: \(message)") }
}

/// Records what reaches the island: the glance, the page and its opening.
@MainActor
final class MediaPresenter: IslandPresenting, IslandMediaPresenting {
    var media: [IslandMedia?] = []
    var tap: (@MainActor () -> Void)?
    var pages: [String: IslandPage] = [:]
    var opened: [String] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    func setMedia(_ media: IslandMedia?, owner: String, onTap: (@MainActor () -> Void)?) {
        check(owner == SpotifyIsland.owner, "one owner")
        self.media.append(media)
        tap = onTap
    }
    func setPage(_ page: IslandPage?, owner: String) { pages[owner] = page }
    func openPage(owner: String) { opened.append(owner) }
    func closePage(owner: String) {}
}

/// No Soloist key, so nothing launches; covers come from the fake transport and nothing touches the network.
@MainActor
final class Fake {
    static var shared = Fake()
    var requests: [String] = []
    let cover = Data("cover-bytes".utf8)

    var system: SpotifySystem {
        SpotifySystem(
            now: { Date(timeIntervalSince1970: 1_800_000_000) }, soloistKey: { nil }, setSoloistKey: { _ in },
            tokens: { nil }, setTokens: { _ in }, installedBuild: { nil },
            install: { throw SoloistInstallError.install },
            launch: { _, _, _, _ in throw SoloistLaunchError.notInstalled },
            connect: { _, _, _ in SoloistLink(send: { _ in }, close: {}) },
            wake: { _, _ in {} },
            nowPlaying: SpotifyNowPlayingSink(update: { _, _ in }, commands: { _ in }),
            web: SpotifyWebTransport(
                send: { request in
                    let body = await MainActor.run {
                        Fake.shared.requests.append(request.url?.absoluteString ?? "")
                        return Fake.shared.cover
                    }
                    return .init(status: 200, body: body, retryAfter: nil)
                },
                listen: { _, _, _ in throw CancellationError() }),
            openURL: { _ in })
    }
}

@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

func song(_ id: String, playing: Bool) -> SpotifyPlayback {
    var playback = SpotifyPlayback()
    playback.status = playing ? .playing : .paused
    playback.volume = 50
    playback.track = SpotifyTrack(id: "spotify:track:\(id)", title: "Paper Lanterns \(id)", artists: ["Juno Vale", "Kit"],
        album: nil, artworkURL: URL(string: "https://i.scdn.co/large/\(id)"),
        thumbnailURL: URL(string: "https://i.scdn.co/small/\(id)"), durationMs: 200_000)
    return playback
}

@main
struct SpotifyIslandTests {
    @MainActor
    static func main() async {
        let suite = "nc-spotify-island-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") }
        let presenter = MediaPresenter()
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: SpotifyAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date() }, onTapsChanged: {})
        guard let module = SpotifyAddon.makeModule(context) as? SpotifyModule else { preconditionFailure("module") }
        context.attach(module)

        module.start()
        await settle()
        check(presenter.pages[SpotifyIsland.owner]?.size == SpotifyPlayerView.pageSize, "on registers the page")
        check(presenter.media.compactMap { $0 }.isEmpty, "no song, no glance (D8)")

        module.apply(song("1", playing: true))
        let first = presenter.media.last??.id
        check(first == "spotify:track:1", "a loaded song shows")
        check(presenter.media.last??.subtitle == "Juno Vale, Kit" && presenter.media.last??.isPlaying == true, "names")
        check(presenter.media.last??.overflow == .fit, "fit by default (D15)")
        await settle()
        check(Fake.shared.requests == ["https://i.scdn.co/small/1"], "the small cover is fetched once")
        check(presenter.media.last??.artwork == Fake.shared.cover, "and drawn once it lands")

        module.apply(song("1", playing: false))
        await settle()
        check(presenter.media.last??.isPlaying == false && presenter.media.last??.artwork != nil, "paused keeps cover")
        check(Fake.shared.requests.count == 1, "the same cover is not fetched again")

        module.island.overflow = .scroll
        check(presenter.media.last??.overflow == .scroll, "the Settings choice reaches the pill at once")
        check(defaults.string(forKey: SpotifyIsland.overflowKey) == "scroll", "and is kept")

        presenter.tap?()
        check(presenter.opened == [SpotifyIsland.owner], "a click on the glance opens the player")

        let page = presenter.pages[SpotifyIsland.owner]
        check(page?.onKey(.up) == true && module.playback.volume == 55, "up raises Spotify's volume")
        check(page?.onKey(.down) == true && module.playback.volume == 50, "down lowers it")

        let expand = SpotifyAddon.commands.first { $0.id == "command:nc-spotify-expand-player" }
        check(expand?.hyperDefault == kVK_ANSI_S && expand?.switchID == "spotify", "Expand Player defaults to Hyper+S")
        expand?.run(context)
        check(presenter.opened.count == 2, "the command opens the player")

        module.apply(SpotifyPlayback())
        check(presenter.media.last! == nil, "stop or clear hides the glance (D8)")

        module.apply(song("2", playing: true))
        await settle()
        check(presenter.media.last??.id == "spotify:track:2" && Fake.shared.requests.count == 2, "a new song, its cover")

        module.stop()
        check(presenter.media.last! == nil && presenter.pages.isEmpty, "off removes the glance and the page")
        print("Spotify island: glance, cover, overflow, page keys and Expand Player hold")
    }
}
