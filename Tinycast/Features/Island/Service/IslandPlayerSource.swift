import Foundation

/// A player behind the Player page; `IslandPresenting.showPlayer` routes the page's buttons to it.
@MainActor
protocol IslandPlayerSource: AnyObject {
    func perform(_ action: IslandPlayerAction)
}

extension IslandPresenting {
    /// The Player page and the song glance for whichever player is playing; nil removes both.
    func showPlayer(_ playing: IslandNowPlaying?, source: any IslandPlayerSource) {
        setSong(playing?.glance)
        setPage(playing.map(IslandPlayerPage.page), id: IslandPlayerPage.id) { [weak source] id in
            if let action = IslandPlayerAction(id: id) { source?.perform(action) }
        }
    }
}

