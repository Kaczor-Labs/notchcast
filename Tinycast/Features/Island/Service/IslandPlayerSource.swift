import Foundation

/// A player behind the Player page; `IslandPresenting.showPlayer` routes the page's buttons to it.
@MainActor
protocol IslandPlayerSource: AnyObject {
    func perform(_ control: IslandPlayerControl)
}

extension IslandPresenting {
    /// The Player page and the song glance for whichever player is playing; nil removes both.
    func showPlayer(_ playing: IslandNowPlaying?, source: any IslandPlayerSource) {
        (self as? any IslandSongPresenting)?.setSong(playing)
        setPage(playing.map(IslandPlayerPage.page), id: IslandPlayerPage.id) { [weak source] id in
            if let control = IslandPlayerControl(rawValue: id) { source?.perform(control) }
        }
    }
}

/// The presenter that draws the song glance (D7, D8); a harness's recorder draws none.
@MainActor
protocol IslandSongPresenting: AnyObject {
    /// The loaded song in the resting pill, below a meeting glance; nil clears it.
    func setSong(_ song: IslandNowPlaying?)
}
