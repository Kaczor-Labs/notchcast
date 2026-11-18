import Foundation

/// Any add-on's loaded song for the resting pill: cover left, a playing or paused glyph right.
struct IslandMedia: Equatable, Sendable {
    /// Changes with the song, so a new one can announce itself once.
    var id: String
    var title: String
    var subtitle: String
    /// Encoded image bytes; nil draws the placeholder tile.
    var artwork: Data?
    var isPlaying: Bool
    /// How a notchless pill fits a line longer than its cap.
    var overflow = IslandMediaOverflow.fit

    /// VoiceOver's value for the pill: the full names and the state, never cut.
    var accessibilityValue: String {
        let state = isPlaying ? String(localized: "Playing", table: "Notchcast")
                              : String(localized: "Paused")
        return [title, subtitle, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// D15: the notchless pill either grows to its line or keeps the cap and scrolls the line.
enum IslandMediaOverflow: String, Sendable, CaseIterable {
    case fit
    case scroll
}

/// The notchless pill's line of title and subtitle; past its cap it either cuts or scrolls.
struct IslandMediaLine: Equatable, Sendable {
    let width: Double
    let scrolls: Bool

    /// `text` is the natural width of "title · subtitle"; `cap` the widest the line may get.
    init(text: Double, cap: Double, overflow: IslandMediaOverflow) {
        scrolls = overflow == .scroll && text > cap
        width = min(text, cap)
    }

    /// Still for `pause`, then left at `speed` until the copy `gap` behind reaches the start.
    static func offset(text: Double, gap: Double, speed: Double, pause: Double, at time: Double) -> Double {
        let travel = text + gap
        guard travel > 0, speed > 0 else { return 0 }
        let cycle = pause + travel / speed
        let into = time.truncatingRemainder(dividingBy: cycle)
        return into < pause ? 0 : (into - pause) * speed
    }
}

/// The playing glyph: bars that move like a meter, from time alone (no audio tap, D24).
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

/// D16: a new song shows its title below a notch for one message dwell; never without a notch.
struct IslandSongChange: Equatable, Sendable {
    private(set) var shown: String?
    private(set) var until: TimeInterval = 0
    private var last: String?
    let seconds: TimeInterval

    init(seconds: TimeInterval = IslandNotice.messageSeconds) { self.seconds = seconds }

    /// The first song seen only arms it, so a relaunch never announces what was already loaded.
    mutating func update(_ media: IslandMedia?, notch: Bool, at now: TimeInterval) -> Bool {
        defer { last = media?.id ?? last }
        guard let media, let last, media.id != last, notch else {
            if media == nil || !notch { shown = nil }
            return false
        }
        shown = media.id
        until = now + seconds
        return true
    }

    func remaining(at now: TimeInterval) -> TimeInterval? {
        shown == nil ? nil : max(until - now, 0)
    }

    mutating func expire(at now: TimeInterval) {
        if now >= until { shown = nil }
    }

    /// A level, notice or open page cuts the change short; it does not come back.
    mutating func cut() { shown = nil }
}
