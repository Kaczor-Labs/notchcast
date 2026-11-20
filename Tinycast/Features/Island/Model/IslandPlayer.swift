import Foundation

/// The line of title and artist on a pill without a notch; past its cap it either cuts or scrolls.
struct IslandSongLine: Equatable, Sendable {
    let width: Double
    let scrolls: Bool

    /// `text` is the natural width of "title · artist"; `cap` the widest the line may get.
    init(text: Double, cap: Double, overflow: IslandSongOverflow) {
        scrolls = overflow == .scroll && text > cap
        width = min(text, cap)
    }

    /// Still for `pause`, then left at `speed` until the copy `gap` behind reaches the start.
    static func offset(text: Double, gap: Double, speed: Double, pause: Double, at time: Double) -> Double {
        let travel = text + gap
        guard travel > 0, speed > 0 else { return 0 }
        let into = time.truncatingRemainder(dividingBy: pause + travel / speed)
        return into < pause ? 0 : (into - pause) * speed
    }
}

/// The playing glyph: bars that move like a meter, from time alone, with no audio tap (D24).
enum IslandEqualizer {
    static let bars = 4
    /// The lowest a bar sinks, as a share of its cell, so it never vanishes into a gap.
    static let floor = 0.22

    /// Each bar sums two sines at unrelated rates, so the row never visibly repeats.
    static func levels(at time: Double, playing: Bool) -> [Double] {
        guard playing else { return Array(repeating: floor, count: bars) }
        let rates: [(Double, Double)] = [(5.3, 8.9), (7.1, 3.7), (4.3, 11.3), (6.7, 5.9)]
        let phases: [Double] = [0, 1.7, 3.1, 4.6]
        return (0..<bars).map { index in
            let (slow, fast) = rates[index]
            let wave = 0.6 * sin(time * slow + phases[index]) + 0.4 * sin(time * fast + phases[index] * 2)
            return floor + (1 - floor) * (wave + 1) / 2
        }
    }
}

/// D16: a new song shows below a notch for one message dwell; never without a notch, never the first.
struct IslandSongChange: Equatable, Sendable {
    private(set) var shown: String?
    private var last: String?
    let seconds: TimeInterval

    init(seconds: TimeInterval = IslandNotice.messageSeconds) { self.seconds = seconds }

    /// The first song seen only arms it, so a launch never announces what was already loaded.
    mutating func update(_ song: IslandNowPlaying?, notch: Bool) -> Bool {
        let id = song?.songID
        defer { last = id ?? last }
        guard let id, let last, id != last, notch else {
            if id == nil || !notch { shown = nil }
            return false
        }
        shown = id
        return true
    }

    /// Its dwell's end, or a level, notice, meeting or the open island; it does not come back.
    mutating func cut() { shown = nil }
}

/// The player page's buttons and keys; the raw value is the id its page sends back.
enum IslandPlayerControl: String, Sendable {
    case previous = "player.previous"
    case playPause = "player.playPause"
    case next = "player.next"
    case like = "player.like"
    case refresh = "refresh"
    case volumeUp = "key.up"
    case volumeDown = "key.down"
}

/// What the player page asks of its player: a control, or a seek or volume as a fraction.
enum IslandPlayerAction: Equatable, Sendable {
    case control(IslandPlayerControl)
    case seek(Double)
    case volume(Double)

    /// Space and the arrows on the page are the transport (#850 D27).
    init?(id: String) {
        if let control = IslandPlayerControl(rawValue: id) {
            self = .control(control)
        } else if let fraction = IslandMedia.value(of: IslandMedia.seekAction, in: id) {
            self = .seek(fraction)
        } else if let fraction = IslandMedia.value(of: IslandMedia.volumeAction, in: id) {
            self = .volume(fraction)
        } else {
            switch id {
            case "key.space": self = .control(.playPause)
            case "key.left": self = .control(.previous)
            case "key.right": self = .control(.next)
            default: return nil
            }
        }
    }
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
                                    label: String(localized: "Previous Track"))
        let skip = IslandPageButton(id: IslandPlayerControl.next.rawValue, symbol: "forward.fill",
                                    label: String(localized: "Next Track"))
        let like = playing.liked.map { liked in
            liked ? IslandPageButton(id: IslandPlayerControl.like.rawValue, symbol: "heart.fill",
                                     label: String(localized: "Remove from Liked Songs", table: "Notchcast"))
                  : IslandPageButton(id: IslandPlayerControl.like.rawValue, symbol: "heart",
                                     label: String(localized: "Save to Liked Songs", table: "Notchcast"))
        }
        let upNext = playing.upNext.map { IslandPageRow(title: $0.title, detail: $0.artist) }
        return IslandPage(
            id: id, title: String(localized: "Player", table: "Notchcast"), symbol: "music.note", order: order,
            line: IslandPageLine(symbol: "music.note", artwork: playing.artwork, text: playing.title,
                                 detail: playing.artist, buttons: [toggle, skip]),
            blocks: [.media(IslandMedia(artwork: playing.artwork, title: playing.title, subtitle: playing.artist,
                                        time: playing.time, buttons: [back, toggle, skip], like: like,
                                        seekable: playing.seekable, volume: playing.volume, upNext: upNext))],
            takesKeys: true)
    }
}
