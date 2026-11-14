import Foundation

/// How a changed character turns over, in seconds from the change.
public struct NumberMotion: Sendable, Equatable {
    /// A span of the turn, in seconds.
    public struct Window: Sendable, Equatable {
        public var from: Double
        public var to: Double

        public init(_ from: Double, _ to: Double) {
            self.from = from
            self.to = to
        }
    }

    /// Seconds the incoming character waits; its windows count from there.
    public var inDelay = 0.2
    /// Peak blur in px per px of font size, before the character's scale.
    public var blurPerEm = 0.14
    public var outShrink = Window(0.03, 0.21)
    /// Scale the outgoing character shrinks to.
    public var outScale = 0.7
    public var outFade = Window(0.19, 0.26)
    /// Scale the incoming character grows from.
    public var inScale = 0.72
    public var inGrow = Window(0, 0.25)
    public var inFade = Window(0, 0.16)
    /// Ease-out power of the incoming fade; 1 is linear.
    public var inFadeEase = 1.0
    public var inSharpen = Window(0, 0.28)
    /// How far a character travels as it turns, in em.
    public var roll = 0.0
    /// Seconds of the crossfade a place gets when it changes again before its turn has ended.
    public var retarget = 0.12

    public static let standard = NumberMotion()

    public init() {}

    /// Seconds a full turn lasts: the incoming character is sharp and in, the outgoing one gone.
    public var rollEnd: Double {
        max(inDelay + max(inSharpen.to, inFade.to, inGrow.to), outFade.to, outShrink.to)
    }
}

/// What a span of a place draws: one character and how it looks.
public struct NumberGlyph: Sendable, Equatable {
    /// The character, or "" when the span draws nothing.
    public var character: String
    public var opacity: Double
    /// Blur radius in px, drawn to two decimals; 0 when no blur is applied.
    public var blur: Double
    /// Vertical offset in px.
    public var offsetY: Double
    public var scale: Double
    /// A hidden span that was put at rest: its offset and scale are left over, not computed.
    public var isStale: Bool
}

/// One place of the text, drawn from the left.
public enum NumberPlace: Sendable, Equatable {
    /// A place that has not turned at this length: just its character.
    case plain(String)
    /// A place that has turned: the incoming span, and the outgoing spans under it, bottom first.
    case cell(incoming: NumberGlyph, outgoing: [NumberGlyph])
}

/// What a `set` started.
public struct NumberChange: Sendable, Equatable {
    /// Places whose character changed, so a turn began.
    public var turned = 0
    /// Of those, places that were still turning and crossfaded out of where they were.
    public var retargeted = 0
}

/// Text whose changed characters turn over with a blur, aligned from the right.
///
/// The caller drives it with explicit clock times in milliseconds: `set` on a new text, then read
/// `places(at:)` on every frame until `isAtRest(at:)`.
public struct NumberTurn: Sendable {
    private struct Pose {
        var opacity: Double
        var blur: Double
        var scale: Double
        var rise: Double
    }

    private struct Glyph {
        var char: Unicode.Scalar?
        var pose: Pose
    }

    private struct Fading {
        var char: Unicode.Scalar?
        var pose: Pose
        /// Seconds into its fade when the turn that holds it began.
        var since: Double
    }

    private enum Motion {
        case roll(from: Unicode.Scalar?)
        case retarget([Fading])
    }

    private struct Turn {
        var at: Double
        var motion: Motion
    }

    private struct Change {
        var turns: [Int: Turn]
        var cells: Set<Int>
    }

    /// The most glyphs a retarget keeps fading out besides the one coming in.
    private static let maxRetained = 4

    private let motion: NumberMotion
    private var reduced: Bool
    private var pace: Double
    private var fontSize: Double
    private var capturedEm: Double
    private var blurMax: Double { reduced ? 0 : motion.blurPerEm * capturedEm }
    private var roll: Double { reduced ? 0 : motion.roll * capturedEm }
    private var shown: [Unicode.Scalar]
    private var change: Change?

    /// - Parameters:
    ///   - turn: Seconds a changed character takes; nil, or 0 and below, keeps the table's turn.
    ///   - fontSize: Size of the text in px, which scales the blur. 0 and NaN count as 16.
    public init(
        _ text: String, turn: Double? = nil, fontSize: Double = 16, reducedMotion: Bool = false,
        motion: NumberMotion = .standard
    ) {
        self.motion = motion
        reduced = reducedMotion
        pace = turn.map { $0 <= 0 ? 1 : motion.rollEnd / $0 } ?? 1
        self.fontSize = fontSize
        capturedEm = fontSize.isNaN || fontSize == 0 ? 16 : fontSize
        shown = Array(text.unicodeScalars)
    }

    /// Re-poses the same turns at their original start times; font changes wait for an effect dependency.
    public mutating func reconfigure(turn: Double?, fontSize: Double, reducedMotion: Bool, clockChanged: Bool = false) {
        self.fontSize = fontSize
        let nextPace = turn.map { $0 <= 0 ? 1 : motion.rollEnd / $0 } ?? 1
        if reduced != reducedMotion || pace != nextPace || clockChanged {
            capturedEm = fontSize.isNaN || fontSize == 0 ? 16 : fontSize
        }
        reduced = reducedMotion
        pace = nextPace
    }

    /// The text now shown.
    public var text: String {
        var text = String.UnicodeScalarView()
        text.append(contentsOf: shown)
        return String(text)
    }

    /// Shows `text` from clock time `ms`. Characters that differ from what the place showed turn;
    /// the rest stay. A place still turning crossfades out of where it is.
    @discardableResult
    public mutating func set(_ text: String, at ms: Double) -> NumberChange {
        let next = Array(text.unicodeScalars)
        if next == shown { return NumberChange() }
        let units = Self.utf16Count(next)
        // Places count scalars but the padding counts UTF-16 units, so astral characters misalign.
        let padded: [Unicode.Scalar?] = Array(repeating: nil, count: max(0, units - shown.count)) + shown.map { $0 }
        let from = units == 0 ? padded : Array(padded.suffix(units))
        let sameLength = change != nil && Self.utf16Count(shown) == units
        var turns: [Int: Turn] = [:]
        if sameLength, let change {
            for (index, turn) in change.turns where seconds(since: turn.at, ms) < length(of: turn.motion) {
                turns[index] = turn
            }
        }
        var result = NumberChange()
        var turning: [Int] = []
        for (index, scalar) in next.enumerated() {
            let old = index < from.count ? from[index] : nil
            if old == scalar { continue }
            turning.append(index)
            let previous = turns[index]
            turns[index] = startTurn(previous: previous, from: old, now: ms)
            result.turned += 1
            if case .retarget? = turns[index]?.motion { result.retargeted += 1 }
        }
        let kept: Set<Int> = sameLength ? change?.cells ?? [] : []
        shown = next
        change = Change(turns: turns, cells: kept.union(turning))
        capturedEm = fontSize.isNaN || fontSize == 0 ? 16 : fontSize
        return result
    }

    /// The places as drawn at clock time `ms`.
    public func places(at ms: Double) -> [NumberPlace] {
        shown.enumerated().map { index, scalar in
            let character = String(scalar)
            guard let change, change.cells.contains(index) else { return .plain(character) }
            guard let turn = change.turns[index] else {
                return .cell(
                    incoming: NumberGlyph(character: character, opacity: 1, blur: 0, offsetY: 0, scale: 1, isStale: false),
                    outgoing: [Self.hidden])
            }
            let poses = poses(of: turn.motion, at: seconds(since: turn.at, ms))
            let spans = (0..<max(1, poses.outgoing.count)).map { k in
                k < poses.outgoing.count ? glyph(poses.outgoing[k].char, poses.outgoing[k].pose) : Self.hidden
            }
            return .cell(incoming: glyph(scalar, poses.incoming), outgoing: spans)
        }
    }

    /// Whether every turn has ended by `ms`, so frames are no longer needed.
    public func isAtRest(at ms: Double) -> Bool {
        change?.turns.values.allSatisfy { !(seconds(since: $0.at, ms) < length(of: $0.motion)) } ?? true
    }

    private static let hidden = NumberGlyph(character: "", opacity: 0, blur: 0, offsetY: 0, scale: 1, isStale: true)

    private static func utf16Count(_ scalars: [Unicode.Scalar]) -> Int {
        scalars.reduce(0) { $0 + ($1.value > 0xFFFF ? 2 : 1) }
    }

    private func seconds(since at: Double, _ ms: Double) -> Double { ((ms - at) / 1000) * pace }

    private func glyph(_ char: Unicode.Scalar?, _ pose: Pose) -> NumberGlyph {
        let blur = blurMax * pose.blur
        return NumberGlyph(
            character: char.map { String($0) } ?? "", opacity: pose.opacity, blur: blur > 0.01 ? blur : 0,
            offsetY: roll * pose.rise, scale: pose.scale, isStale: false)
    }

    private func length(of motion: Motion) -> Double {
        switch motion {
        case .roll: self.motion.rollEnd
        case .retarget: self.motion.retarget
        }
    }

    private func rollOut(_ t: Double) -> Pose {
        let shrink = reduced ? 0 : ramp(t, motion.outShrink)
        return Pose(
            opacity: reduced ? 1 - linear(t, motion.inFade) : 1 - ramp(t, motion.outFade),
            blur: t >= motion.outFade.to ? 0 : shrink,
            scale: 1 - (1 - motion.outScale) * shrink,
            rise: -ramp(t, motion.outFade))
    }

    private func rollIn(_ t: Double) -> Pose {
        let tIn = t - (reduced ? 0 : motion.inDelay)
        return Pose(
            opacity: 1 - pow(1 - linear(tIn, motion.inFade), motion.inFadeEase),
            blur: 1 - linear(tIn, motion.inSharpen),
            scale: motion.inScale + (1 - motion.inScale) * (reduced ? 1 : ramp(tIn, motion.inGrow)),
            rise: 1 - ramp(tIn, motion.inFade))
    }

    private func poses(of motion: Motion, at t: Double) -> (incoming: Pose, outgoing: [Glyph]) {
        switch motion {
        case .roll(let from):
            return (rollIn(t), [Glyph(char: from, pose: rollOut(t))])
        case .retarget(let from):
            let window = NumberMotion.Window(0, self.motion.retarget)
            let outgoing = from.map { fading in
                let fade = linear(t + fading.since, window)
                var pose = fading.pose
                pose.opacity = fading.pose.opacity * (1 - fade)
                pose.blur = fade >= 1 ? 0 : fading.pose.blur
                return Glyph(char: fading.char, pose: pose)
            }
            return (Pose(opacity: linear(t, window), blur: 0, scale: 1, rise: 0), outgoing)
        }
    }

    /// The turn a place starts. One still turning retargets: every glyph it draws now fades out.
    private func startTurn(previous: Turn?, from: Unicode.Scalar?, now: Double) -> Turn {
        guard let previous else { return Turn(at: now, motion: .roll(from: from)) }
        let t = seconds(since: previous.at, now)
        if t >= length(of: previous.motion) { return Turn(at: now, motion: .roll(from: from)) }
        let (incoming, outgoing) = poses(of: previous.motion, at: t)
        let caught: [Fading]
        if case .retarget(let glyphs) = previous.motion {
            caught = glyphs.map { Fading(char: $0.char, pose: $0.pose, since: $0.since + t) }
        } else {
            caught = outgoing.map { Fading(char: $0.char, pose: $0.pose, since: 0) }
        }
        let window = NumberMotion.Window(0, motion.retarget)
        func opacity(_ glyph: Fading) -> Double { glyph.pose.opacity * (1 - linear(glyph.since, window)) }
        let live = ([Fading(char: from, pose: incoming, since: 0)] + caught).filter { opacity($0) > 0 }
        let faintest = live.indices
            .sorted { (opacity(live[$0]), $0) < (opacity(live[$1]), $1) }
            .prefix(max(0, live.count - Self.maxRetained))
        let dropped = Set(faintest)
        return Turn(at: now, motion: .retarget(live.indices.filter { !dropped.contains($0) }.map { live[$0] }))
    }
}

private func ramp(_ t: Double, _ window: NumberMotion.Window) -> Double {
    let u = jsMin(1, jsMax(0, (t - window.from) / jsMax(window.to - window.from, 1e-4)))
    return u * u * (3 - 2 * u)
}

private func linear(_ t: Double, _ window: NumberMotion.Window) -> Double {
    jsMin(1, jsMax(0, (t - window.from) / jsMax(window.to - window.from, 1e-4)))
}
