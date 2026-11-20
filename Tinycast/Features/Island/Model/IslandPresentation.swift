import Foundation

/// Any caller's HUD level: Tinycast volume now, add-on volume keys, brightness or backlight later.
struct IslandLevel: Equatable, Sendable {
    var source: String
    var symbol: String
    var label: String
    var value: Double
    var range: ClosedRange<Double> = 0...1 // outside 0...1 draws as outlined zones past the track
}

/// A reposted `id` updates in place; a `progress` notice stays until ended or reposted without it.
struct IslandNotice: Equatable, Sendable {
    var id: String
    var symbol: String?
    var text: String
    var progress: IslandProgress?
    var isFailure = false
    /// Unset, a notice dwells as the stock message HUD does; a failure dwells longer (design §10).
    var seconds: TimeInterval?
    /// What VoiceOver says instead of `text`, when the text shows something it must not read aloud.
    var spokenText: String?

    static let messageSeconds: TimeInterval = 2.4
    static let failureSeconds: TimeInterval = 4

    var spoken: String { spokenText ?? text }
    var dwell: TimeInterval { seconds ?? (isFailure ? Self.failureSeconds : Self.messageSeconds) }
    /// On a notch, its text expands below the notch; otherwise it keeps to the wings (design §10).
    var isHeadline: Bool { progress?.headline ?? true }
}

/// A nil `fraction` is unknown, so the pill shows the notice's glyph rather than a made-up ring.
struct IslandProgress: Equatable, Sendable {
    var fraction: Double?
    /// The text is a title worth one message dwell below the notch before the ring takes the wing.
    var headline = true
}

/// A rest-pill glyph that stays until its owner clears it; at most four `text` characters show.
struct IslandStatus: Equatable, Sendable {
    var id: String
    var symbol: String
    var text: String?
    var label: String
}

/// An add-on's pill-menu row; an unchecked row keeps its check column empty, so rows line up.
struct IslandMenuRow: Equatable, Sendable {
    var id: String
    var title: String
    var isChecked = false
}

/// One topic in the open island, described as data; the island draws it from design-system tokens (#975).
struct IslandPage: Equatable, Sendable {
    /// The owner's id, one page per owner; also the tab's identity.
    var id: String
    var title: String
    var symbol: String
    /// Tabs run in this order; Home lists badged pages first, then this order.
    var order: Int
    /// Something waits for the user: a count on the tab, and the Home line moves to the top.
    var badge = 0
    /// The page summed up in one Home line.
    var line: IslandPageLine
    var blocks: [IslandPageBlock]
    /// Set, space and the four arrows on this page go to `onAction` as `IslandPageKey.action` ids.
    var takesKeys = false

    /// What Command-R sends to `onAction`; every page refreshes its data on it.
    static let refreshAction = "refresh"
}

/// A Home line: a glyph or artwork, one text with an optional detail, and inline buttons.
struct IslandPageLine: Equatable, Sendable {
    var symbol: String?
    /// Encoded image bytes; drawn instead of the glyph when they decode.
    var artwork: Data?
    var text: String
    var detail: String?
    var buttons: [IslandPageButton] = []
    /// Set, a click on the line sends this to `onAction` instead of opening the page's tab.
    var action: String?
}

/// An icon button; `label` is its VoiceOver name and tooltip, `id` what `onAction` receives.
struct IslandPageButton: Equatable, Sendable {
    var id: String
    var symbol: String
    var label: String
    /// Off, the button shows dimmed and takes no click.
    var isEnabled = true
}

/// The vocabulary a page body is written in; a new kind is drawn once in `IslandPageBlocks`.
enum IslandPageBlock: Equatable, Sendable {
    case media(IslandMedia)
    case row(IslandPageRow)
    case meter(IslandPageMeter)
    /// Titled columns of cards in fixed slots: a full card one slot, a hollow one half (#1128).
    case columns([IslandCardGroup])
    /// A titled row of cards, four across, each as tall as the tallest.
    case cards(IslandCardGroup)
}

/// A playing item: artwork, title, subtitle, a running time and transport buttons.
struct IslandMedia: Equatable, Sendable {
    var artwork: Data?
    var title: String
    var subtitle: String?
    var time: IslandMediaTime?
    var buttons: [IslandPageButton]
    /// A toggle beside the title, such as a heart; nil draws none.
    var like: IslandPageButton?
    /// A click or drag on the bar sends `IslandMedia.seekAction` with the fraction.
    var seekable = false
    /// 0...1; set, a volume bar under the transport sends `IslandMedia.volumeAction` with the level.
    var volume: Double?
    /// What plays next, listed beside the player under "Up Next" as plain rows.
    var upNext: [IslandPageRow] = []

    static let seekAction = "media.seek"
    static let volumeAction = "media.volume"

    /// "<action>:<fraction>", the one string `onAction` carries; `value(of:in:)` reads it back.
    static func action(_ name: String, _ fraction: Double) -> String {
        "\(name):\(min(max(fraction, 0), 1))"
    }

    static func value(of name: String, in id: String) -> Double? {
        guard id.hasPrefix(name + ":"), let value = Double(id.dropFirst(name.count + 1)), value.isFinite else {
            return nil
        }
        return min(max(value, 0), 1)
    }
}

/// "At `sampledAt` it was `elapsed` seconds in, moving at `rate`", so the bar runs without updates.
struct IslandMediaTime: Equatable, Sendable {
    var elapsed: TimeInterval
    var duration: TimeInterval
    var rate: Double
    var sampledAt: Date

    func elapsed(at now: Date) -> TimeInterval {
        min(max(elapsed + now.timeIntervalSince(sampledAt) * rate, 0), max(duration, 0))
    }

    func fraction(at now: Date) -> Double { duration > 0 ? elapsed(at: now) / duration : 0 }
}

/// A list row; a row with an `id` is a button that sends it to `onAction`.
struct IslandPageRow: Equatable, Sendable {
    var id: String?
    var symbol: String?
    var title: String
    var detail: String?
    var trailing: String?
    /// What VoiceOver reads instead of the row, as a notice's `spokenText`.
    var spoken: String?
}

/// A labelled bar, 0...1, with its value as text.
struct IslandPageMeter: Equatable, Sendable {
    var label: String
    var fraction: Double
    var value: String
}

/// A titled set of cards: one column of a `columns` block, or the row of a `cards` block.
struct IslandCardGroup: Equatable, Sendable {
    var title: String
    var cards: [IslandCard]
}

/// A card: a title and an optional chip over meters or one notice; a hollow card is an outline.
struct IslandCard: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        case meters([IslandCardMeter])
        case notice(symbol: String?, headline: String, detail: String?)
    }

    var title: String
    var tag: IslandCardTag?
    var hollow = false
    var body: Body
    /// Out of date: the whole card at the disabled opacity.
    var dimmed = false
    /// A secondary line under the body, such as how old its numbers are.
    var caption: String?
    /// VoiceOver reads the card as one element; nil reads its texts in order.
    var spoken: String?
}

struct IslandCardTag: Equatable, Sendable {
    var symbol: String?
    var text: String
}

/// A limit's bar: label, value and trailing text over it, a tick on it, a note under it.
struct IslandCardMeter: Equatable, Sendable {
    var label: String
    var value: String
    var trailing: String?
    var fraction: Double
    /// Where an even pace puts the fill now, 0...1.
    var tick: Double?
    var thick = false
    /// The value, the fill and the note take the warning ink.
    var warning = false
    var note: String?
}

/// What any player shows on the island: Spotify now, the any-player source (#930) later.
struct IslandNowPlaying: Equatable, Sendable {
    var title: String
    var artist: String?
    var artwork: Data?
    var time: IslandMediaTime?
    var isPlaying: Bool
    /// Changes with the song, so a new one announces itself once; empty falls back to the names.
    var id = ""
    /// How a pill without a notch fits "title · artist" longer than its cap (D15).
    var overflow = IslandSongOverflow.widen
    /// In the user's liked songs; nil when the player cannot tell, so no heart shows.
    var liked: Bool?
    /// The player is still asking about this song, so the heart shows dimmed instead of a guess.
    var likePending = false
    /// 0...1; nil hides the volume bar.
    var volume: Double?
    /// The player takes a seek on the bar.
    var seekable = false
    var upNext: [IslandQueuedSong] = []

    /// Only what the pill draws, so a change to the page alone never redraws it.
    var glance: IslandNowPlaying {
        IslandNowPlaying(title: title, artist: artist, artwork: artwork, time: nil, isPlaying: isPlaying, id: id,
                         overflow: overflow)
    }

    var songID: String { id.isEmpty ? title + "\u{1F}" + (artist ?? "") : id }
}

/// A song waiting after this one.
struct IslandQueuedSong: Equatable, Sendable {
    var id: String
    var title: String
    var artist: String?
}

/// D15: a pill without a notch either widens to the song's line or keeps its cap and scrolls the line.
enum IslandSongOverflow: String, Sendable, CaseIterable {
    case widen
    case scroll
}
