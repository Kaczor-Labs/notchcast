import Foundation

/// A player behind the Player page; `IslandPresenting.showPlayer` routes the page's buttons to it.
@MainActor
protocol IslandPlayerSource: AnyObject {
    func perform(_ control: IslandPlayerControl)
}

extension IslandPresenting {
    /// The Player page for whichever player is playing; nil removes it.
    func showPlayer(_ playing: IslandNowPlaying?, source: any IslandPlayerSource) {
        setPage(playing.map(IslandPlayerPage.page), id: IslandPlayerPage.id) { [weak source] id in
            if let control = IslandPlayerControl(rawValue: id) { source?.perform(control) }
        }
    }
}
