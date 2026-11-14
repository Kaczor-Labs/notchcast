import Foundation

/// A progress bar's fill: it springs to each new value, or tweens under reduced motion.
///
/// The caller drives it with explicit clock times in milliseconds: `set` on a new value, then `frame`
/// on every frame until `isRunning` turns false. `painted` is what the fill is drawn at.
public struct ProgressFill: Sendable {
    /// How the fill moves when no spring is given.
    public static let defaultSpring = SpringConfig(response: 0.97, dampingFraction: 0.74)

    /// Seconds the fill takes to reach a new value under reduced motion.
    public static let reducedDuration = 0.2

    /// Distance from its target, as a fraction, below which the fill counts as at rest.
    public static let precision = 0.0005

    private var animated: AnimatedValue
    private var spring: SpringConfig
    private var reducedMotion: Bool

    /// The clamped value the fill is heading to.
    public private(set) var target: Double

    /// The fraction of the track the fill is drawn at: the motion's value at the last drawn frame.
    public private(set) var painted: Double

    /// Whether frames are still needed. The fill stops at the first frame that finds it at rest.
    public private(set) var isRunning = false

    /// - Parameter value: Where the fill starts, at clock time `ms`. Clamped to 0 through 1; NaN counts as 0.
    public init(value: Double, at ms: Double = 0, spring: SpringConfig = ProgressFill.defaultSpring, reducedMotion: Bool = false) {
        let clamped = clamp01(value)
        self.spring = spring
        self.reducedMotion = reducedMotion
        target = clamped
        animated = AnimatedValue(clamped, precision: Self.precision)
        painted = clamped
        retarget(clamped, at: ms)
    }

    /// The share of the bar as a whole percent, as the bar reports it.
    public var percent: Double { jsRound(target * 100) }

    /// Heads for `value` from clock time `ms` and draws the first frame. A value that clamps to the
    /// target already set changes nothing, so a motion in flight carries on.
    public mutating func set(_ value: Double, at ms: Double) {
        let clamped = clamp01(value)
        if clamped == target { return }
        target = clamped
        retarget(clamped, at: ms)
    }

    /// Moves on a new spring or reduced-motion setting from clock time `ms`: the motion in flight,
    /// velocity included, retargets with the new transition, as upstream's effect sets its one value again.
    public mutating func reconfigure(spring: SpringConfig, reducedMotion: Bool, at ms: Double) {
        self.spring = spring
        self.reducedMotion = reducedMotion
        retarget(target, at: ms)
    }

    /// Heads for the current target again from clock time `ms`, carrying on from the motion in flight.
    public mutating func restart(at ms: Double) {
        retarget(target, at: ms)
    }

    /// Draws the frame at `ms` while the fill is moving.
    public mutating func frame(at ms: Double) {
        if isRunning { draw(at: ms) }
    }

    private mutating func retarget(_ value: Double, at ms: Double) {
        let transition: Transition = reducedMotion ? .tween(duration: Self.reducedDuration, delay: 0) : .spring(spring, delay: 0)
        animated.set(value, at: ms / 1000, transition)
        draw(at: ms)
    }

    private mutating func draw(at ms: Double) {
        let t = ms / 1000
        painted = animated.value(at: t)
        isRunning = !animated.isAtRest(at: t)
    }
}
