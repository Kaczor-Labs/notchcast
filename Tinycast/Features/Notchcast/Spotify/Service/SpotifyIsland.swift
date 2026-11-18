import SwiftUI

/// Puts the loaded song in the island's wings and owns the player page under the pill.
@MainActor
final class SpotifyIsland {
    static let owner = "spotify"
    static let overflowKey = "spotifyIslandOverflow"

    private unowned let module: SpotifyModule
    private var artwork: (url: URL, data: Data)?
    private var loading: URL?
    private lazy var covers = SpotifyCovers(send: module.system.web.send)

    init(module: SpotifyModule) { self.module = module }

    private var presenter: (any IslandMediaPresenting)? { module.context.presenter as? any IslandMediaPresenting }

    var overflow: IslandMediaOverflow {
        get { module.context.defaults.string(forKey: Self.overflowKey).flatMap(IslandMediaOverflow.init) ?? .fit }
        set {
            module.context.defaults.set(newValue.rawValue, forKey: Self.overflowKey)
            update(module.playback)
        }
    }

    func start() {
        presenter?.setPage(IslandPage(owner: Self.owner, size: SpotifyPlayerView.pageSize,
            view: { [module, covers] in AnyView(SpotifyPlayerView(module: module).environment(covers)) },
            onKey: { [weak self] in self?.key($0) ?? false }), owner: Self.owner)
        update(module.playback)
    }

    func stop() {
        presenter?.setMedia(nil, owner: Self.owner, onTap: nil)
        presenter?.setPage(nil, owner: Self.owner)
        artwork = nil
        loading = nil
    }

    func expand() { presenter?.openPage(owner: Self.owner) }

    /// D8: the glance shows while a song is loaded, playing or paused.
    func update(_ playback: SpotifyPlayback) {
        guard let track = playback.track else {
            presenter?.setMedia(nil, owner: Self.owner, onTap: nil)
            return
        }
        let url = track.thumbnailURL ?? track.artworkURL
        let data = artwork.flatMap { $0.url == url ? $0.data : nil }
        let media = IslandMedia(id: track.id, title: track.title, subtitle: track.artistLine, artwork: data,
                                isPlaying: playback.isPlaying, overflow: overflow)
        presenter?.setMedia(media, owner: Self.owner) { [weak self] in self?.expand() }
        if let url, data == nil, loading != url { load(url) }
    }

    /// One cover at a time; a song that changed while it loaded keeps the newer one.
    private func load(_ url: URL) {
        loading = url
        let send = module.system.web.send
        Task { [weak self] in
            let response = try? await send(URLRequest(url: url))
            guard let self, self.loading == url else { return }
            self.loading = nil
            guard let response, response.status == 200, !response.body.isEmpty else { return }
            self.artwork = (url, response.body)
            self.update(self.module.playback)
        }
    }

    /// The player's keys while it holds the keyboard (flow §3).
    private func key(_ key: IslandPageKey) -> Bool {
        switch key {
        case .space: module.togglePlay()
        case .left: module.previous()
        case .right: module.next()
        case .up: module.setVolume(module.playback.volume + SpotifyPlayerView.volumeStep)
        case .down: module.setVolume(module.playback.volume - SpotifyPlayerView.volumeStep)
        case .refresh: module.send(.getState)
        }
        return true
    }
}
