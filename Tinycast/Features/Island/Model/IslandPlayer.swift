import Foundation

/// What any player shows on the island: Spotify now, the any-player source (#930) later.
struct IslandNowPlaying: Equatable, Sendable {
    var title: String
    var artist: String?
    var artwork: Data?
    var time: IslandMediaTime?
    var isPlaying: Bool
}

/// The player page's buttons; the raw value is the id its page sends back.
enum IslandPlayerControl: String, Sendable {
    case previous = "player.previous"
    case playPause = "player.playPause"
    case next = "player.next"
    case refresh = "refresh"
}

/// The Player page (#975): artwork, title, artist, time and transport, and its Home line.
enum IslandPlayerPage {
    static let id = "player"
    /// After Agents (0), before System (20) and Day (30), as decision 946-11 orders them.
    static let order = 10

    static func page(_ playing: IslandNowPlaying) -> IslandPage {
        let toggle = playing.isPlaying
            ? IslandPageButton(id: IslandPlayerControl.playPause.rawValue, symbol: "pause.fill",
                               label: String(localized: "Pause", table: "Notchcast"))
            : IslandPageButton(id: IslandPlayerControl.playPause.rawValue, symbol: "play.fill",
                               label: String(localized: "Play", table: "Notchcast"))
        let back = IslandPageButton(id: IslandPlayerControl.previous.rawValue, symbol: "backward.fill",
                                    label: String(localized: "Previous Track", table: "Notchcast"))
        let skip = IslandPageButton(id: IslandPlayerControl.next.rawValue, symbol: "forward.fill",
                                    label: String(localized: "Next Track", table: "Notchcast"))
        return IslandPage(
            id: id, title: String(localized: "Player", table: "Notchcast"), symbol: "music.note", order: order,
            line: IslandPageLine(symbol: "music.note", artwork: playing.artwork, text: playing.title,
                                 detail: playing.artist, buttons: [toggle, skip]),
            blocks: [.media(IslandMedia(artwork: playing.artwork, title: playing.title, subtitle: playing.artist,
                                        time: playing.time, buttons: [back, toggle, skip]))])
    }
}
