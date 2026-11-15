import Foundation

/// One presentation per burst of level calls: each call restarts the dwell, never the presentation.
struct IslandLevelDwell: Equatable, Sendable {
    static let seconds: TimeInterval = 1.5
    private(set) var level: IslandLevel?
    private(set) var deadline: TimeInterval = 0
    /// Counts presentations; a dwell task applies its end only while this is still its token.
    private(set) var presentation = 0

    /// True when the call starts a presentation rather than extending the one on screen.
    mutating func show(_ level: IslandLevel, at now: TimeInterval) -> Bool {
        let fresh = self.level == nil || now >= deadline
        if fresh { presentation += 1 }
        self.level = level
        deadline = now + Self.seconds
        return fresh
    }

    /// Seconds left for `token`, or nil once it is replaced or its dwell has run out.
    mutating func remaining(_ token: Int, at now: TimeInterval) -> TimeInterval? {
        guard token == presentation, level != nil else { return nil }
        guard now < deadline else { level = nil; return nil }
        return deadline - now
    }

    /// Under the palette or a question a level takes the report slot instead of the pill.
    static func stacked(palette: Bool, question: Bool) -> Bool { palette || question }
}

/// Extents along a track `width` wide: 0...1 is the track, the rest of `range` outlined zones.
struct IslandLevelTrack: Equatable, Sendable {
    let below: ClosedRange<Double>?
    let track: ClosedRange<Double>
    let above: ClosedRange<Double>?
    let fill: ClosedRange<Double>

    init(_ level: IslandLevel, width: Double) {
        let low = min(level.range.lowerBound, 0)
        let high = max(level.range.upperBound, 1)
        func x(_ value: Double) -> Double { (value - low) / (high - low) * width }
        let value = min(max(level.value, low), high)
        below = low < 0 ? x(low)...x(0) : nil
        track = x(0)...x(1)
        above = high > 1 ? x(1)...x(high) : nil
        fill = x(min(value, 0))...x(max(value, 0))
    }
}
