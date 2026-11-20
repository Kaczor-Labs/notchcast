import Foundation

/// Spotify's playback as the island's Player page (#975), its cover fetched once per song.
@MainActor
final class SpotifyPlayerPage: IslandPlayerSource {
    /// A cover larger than this is not a cover; the page keeps its glyph.
    static let maxCoverBytes = 4 << 20
    /// "Long song names" (D15): how a pill without a notch fits a long title and artist.
    static let overflowKey = "spotifyLongSongNames"

    private weak var module: SpotifyModule?
    private var cover: (url: URL, data: Data)?
    private var loading: (url: URL, task: Task<Void, Never>)?
    private var last: SpotifyPlayback?

    init(module: SpotifyModule) { self.module = module }

    func update(_ playback: SpotifyPlayback) {
        let newSong = last?.track?.id != playback.track?.id
        last = playback
        guard let module else { return }
        if newSong { module.refreshLiked() }
        guard let track = playback.track else {
            loading?.task.cancel()
            loading = nil
            return module.context.presenter.showPlayer(nil, source: self)
        }
        let artwork = cover.flatMap { $0.url == track.artworkURL ? $0.data : nil }
        let overflow = module.context.defaults.string(forKey: Self.overflowKey).flatMap(IslandSongOverflow.init)
        var playing = Self.nowPlaying(playback, track: track, artwork: artwork, overflow: overflow ?? .widen)
        playing.liked = module.liked
        playing.likePending = module.likePending
        module.context.presenter.showPlayer(playing, source: self)
        if let url = track.artworkURL, url != cover?.url, url != loading?.url { load(url) }
    }

    /// ↑/↓ move Spotify's own volume by this much of 100.
    static let volumeStep = 10

    func perform(_ action: IslandPlayerAction) {
        guard let module else { return }
        switch action {
        case .control(.previous): module.previous()
        case .control(.playPause): module.togglePlay()
        case .control(.next): module.next()
        case .control(.like): module.toggleLike()
        case .control(.refresh):
            module.send(.getState)
            module.refreshLiked()
        case .control(.volumeUp): module.setVolume(module.playback.volume + Self.volumeStep)
        case .control(.volumeDown): module.setVolume(module.playback.volume - Self.volumeStep)
        case .seek(let fraction):
            module.seek(toMs: Int(fraction * Double(module.playback.track?.durationMs ?? 0)))
        case .volume(let fraction): module.setVolume(Int((fraction * 100).rounded()))
        }
    }

    static func nowPlaying(_ playback: SpotifyPlayback, track: SpotifyTrack, artwork: Data?,
                           overflow: IslandSongOverflow = .widen) -> IslandNowPlaying {
        let position = playback.position
        let time = track.durationMs > 0 ? IslandMediaTime(
            elapsed: Double(position.positionMs) / 1000, duration: Double(track.durationMs) / 1000,
            rate: position.speed, sampledAt: position.timestamp) : nil
        let upNext = playback.upNext.prefix(upNextLimit).map {
            IslandQueuedSong(id: $0.id, title: $0.track.title,
                             artist: $0.track.artists.isEmpty ? nil : $0.track.artistLine)
        }
        return IslandNowPlaying(title: track.title, artist: track.artists.isEmpty ? nil : track.artistLine,
                                artwork: artwork, time: time, isPlaying: playback.isPlaying, id: track.id,
                                overflow: overflow, volume: Double(playback.volume) / 100,
                                seekable: playback.actions.contains(.seek), upNext: Array(upNext))
    }

    /// Spotify reports up to ten for a playlist or album; the page lists as many as fit beside the player.
    static let upNextLimit = 5

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
