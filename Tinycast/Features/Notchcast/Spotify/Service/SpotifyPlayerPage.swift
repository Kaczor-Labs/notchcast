import Foundation

/// Spotify's playback as the island's Player page (#975), its cover fetched once per song.
@MainActor
final class SpotifyPlayerPage: IslandPlayerSource {
    /// A cover larger than this is not a cover; the page keeps its glyph.
    static let maxCoverBytes = 4 << 20

    private weak var module: SpotifyModule?
    private var cover: (url: URL, data: Data)?
    private var loading: (url: URL, task: Task<Void, Never>)?
    private var last: SpotifyPlayback?

    init(module: SpotifyModule) { self.module = module }

    func update(_ playback: SpotifyPlayback) {
        last = playback
        guard let module else { return }
        guard let track = playback.track else {
            loading?.task.cancel()
            loading = nil
            return module.context.presenter.showPlayer(nil, source: self)
        }
        let artwork = cover.flatMap { $0.url == track.artworkURL ? $0.data : nil }
        module.context.presenter.showPlayer(Self.nowPlaying(playback, track: track, artwork: artwork), source: self)
        if let url = track.artworkURL, url != cover?.url, url != loading?.url { load(url) }
    }

    func perform(_ control: IslandPlayerControl) {
        switch control {
        case .previous: module?.previous()
        case .playPause: module?.togglePlay()
        case .next: module?.next()
        case .refresh: module?.send(.getState)
        }
    }

    static func nowPlaying(_ playback: SpotifyPlayback, track: SpotifyTrack, artwork: Data?) -> IslandNowPlaying {
        let position = playback.position
        let time = track.durationMs > 0 ? IslandMediaTime(
            elapsed: Double(position.positionMs) / 1000, duration: Double(track.durationMs) / 1000,
            rate: position.speed, sampledAt: position.timestamp) : nil
        return IslandNowPlaying(title: track.title, artist: track.artists.isEmpty ? nil : track.artistLine,
                                artwork: artwork, time: time, isPlaying: playback.isPlaying)
    }

    /// One cover at a time, over the module's private Web API session; a newer song's cover wins.
    private func load(_ url: URL) {
        loading?.task.cancel()
        loading = nil
        guard url.scheme == "https", let web = module?.system.web else { return }
        loading = (url, Task { [weak self] in
            let response: SpotifyWebTransport.Response
            do { response = try await web.send(URLRequest(url: url)) } catch { return }
            guard !Task.isCancelled, let self, response.status == 200, response.body.count <= Self.maxCoverBytes,
                  let last = self.last, last.track?.artworkURL == url else { return }
            self.cover = (url, response.body)
            self.loading = nil
            self.update(last)
        })
    }
}
