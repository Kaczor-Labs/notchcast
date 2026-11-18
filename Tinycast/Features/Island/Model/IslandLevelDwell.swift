import Foundation

/// One presentation per burst of level calls: each call restarts the dwell, never the presentation.
struct IslandLevelDwell: Equatable, Sendable {
    static let seconds: TimeInterval = 1.5
    private(set) var level: IslandLevel?
    private(set) var deadline: TimeInterval = 0
    /// A dwell task applies its end only while this is still its token, so a stale one never clears.
    private(set) var presentation = 0

    mutating func show(_ level: IslandLevel, at now: TimeInterval) -> Bool {
        let fresh = self.level == nil || now >= deadline
        if fresh { presentation += 1 }
        self.level = level
        deadline = now + Self.seconds
        return fresh
    }

    /// Expiry clears the level here, so the dwell task is the only clock.
    mutating func remaining(_ token: Int, at now: TimeInterval) -> TimeInterval? {
        guard token == presentation, level != nil else { return nil }
        guard now < deadline else { level = nil; return nil }
        return deadline - now
    }

    /// The palette's expanded canvas and a question both cover the pill's drawing.
    func placement(palette: Bool, question: Bool) -> IslandLevelPlacement? {
        guard level != nil else { return nil }
        return palette || question ? .band : .pill
    }
}

enum IslandLevelPlacement: Equatable, Sendable {
    case pill, band
}

extension IslandLevel {
    var readout: String { Self.readout(value, in: range) }

    static func readout(_ value: Double, in range: ClosedRange<Double>) -> String { "\(percent(value, in: range))%" }

    /// The whole bar, outlined zones included, spans 0…100, so extra dimming never reads below zero.
    static func percent(_ value: Double, in range: ClosedRange<Double>) -> Int {
        let low = min(range.lowerBound, 0)
        let high = max(range.upperBound, 1)
        let clamped = min(max(value, low), high)
        return Int(((clamped - low) * 100 / (high - low)).rounded())
    }
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
