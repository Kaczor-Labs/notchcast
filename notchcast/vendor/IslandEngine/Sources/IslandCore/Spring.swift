import Foundation

/// A damped spring with SwiftUI's parameters, solved in closed form.
///
/// `response` is the period of the undamped spring in seconds and `dampingFraction` the damping
/// ratio. Mass is 1, so stiffness = (2π / response)² and damping = 4π · dampingFraction / response.
/// Closed form means a value at any time is exact, so a paused clock can seek to any frame.
public struct SpringConfig: Sendable, Hashable, Codable {
    public var response: Double
    public var dampingFraction: Double
    /// Seconds over which a retarget blends from the motion in flight into the new spring.
    public var blendDuration: Double?

    public init(response: Double, dampingFraction: Double, blendDuration: Double? = nil) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }
}

/// Displacement from the target, and velocity.
public struct SpringState: Sendable, Equatable {
    public var x: Double
    public var v: Double
}

/// Displacement and velocity `t` seconds after release from `x0` with velocity `v0`.
public func solveSpring(_ config: SpringConfig, x0: Double, v0: Double, t: Double) -> SpringState {
    let response = jsMax(config.response, 1e-4)
    let zeta = jsMax(config.dampingFraction, 0)
    let w0 = (2 * Double.pi) / response
    if t <= 0 { return SpringState(x: x0, v: v0) }

    if zeta < 1 {
        let wd = w0 * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * w0 * t)
        let b = (v0 + zeta * w0 * x0) / wd
        let cosine = cos(wd * t)
        let sine = sin(wd * t)
        let x = decay * (x0 * cosine + b * sine)
        let v = decay * (-zeta * w0 * (x0 * cosine + b * sine) + (-x0 * wd * sine + b * wd * cosine))
        return SpringState(x: x, v: v)
    }

    if zeta == 1 {
        let decay = exp(-w0 * t)
        let b = v0 + w0 * x0
        let x = decay * (x0 + b * t)
        let v = decay * (b - w0 * (x0 + b * t))
        return SpringState(x: x, v: v)
    }

    let root = (zeta * zeta - 1).squareRoot()
    let r1 = -w0 * (zeta - root)
    let r2 = -w0 * (zeta + root)
    let c2 = (v0 - r1 * x0) / (r2 - r1)
    let c1 = x0 - c2
    let e1 = exp(r1 * t)
    let e2 = exp(r2 * t)
    return SpringState(x: c1 * e1 + c2 * e2, v: c1 * r1 * e1 + c2 * r2 * e2)
}

/// How a value moves to a new target.
public enum Transition: Sendable, Equatable {
    case spring(SpringConfig, delay: Double = 0)
    /// Eased, no overshoot. Used for reduced motion. A duration of 0 is a step after `delay`.
    case tween(duration: Double, delay: Double = 0)
    case instant
}

/// A value and its speed at one instant.
public struct MotionSample: Sendable, Equatable {
    public var value: Double
    public var velocity: Double

    public init(value: Double, velocity: Double) {
        self.value = value
        self.velocity = velocity
    }
}

private struct Leg: Sendable {
    /// Seconds on the island clock when the leg starts.
    var start: Double
    var from: Double
    var to: Double
    var v0: Double
    /// Motion that was in flight when this leg took over, used before `start` and while blending.
    var previous: Segment?
    /// Clock time the leg was asked for, before its delay.
    var issued: Double
}

private indirect enum Segment: Sendable {
    case rest(Double)
    case spring(Leg, SpringConfig)
    case tween(Leg, duration: Double)

    var leg: Leg? {
        switch self {
        case .rest: nil
        case .spring(let leg, _), .tween(let leg, _): leg
        }
    }

    var target: Double {
        switch self {
        case .rest(let value): value
        case .spring(let leg, _), .tween(let leg, _): leg.to
        }
    }

    var settledAfter: Double {
        switch self {
        case .rest: -Double.infinity
        case .tween(let leg, let duration): leg.start + duration
        case .spring(let leg, let spring): leg.start + (spring.blendDuration ?? 0)
        }
    }

    /// Keeps the history one level deep so long chains of retargets don't grow without bound.
    var strippingPrevious: Segment {
        switch self {
        case .rest: return self
        case .spring(var leg, let spring):
            leg.previous = nil
            return .spring(leg, spring)
        case .tween(var leg, let duration):
            leg.previous = nil
            return .tween(leg, duration: duration)
        }
    }

    func sample(at t: Double) -> MotionSample {
        switch self {
        case .rest(let value):
            return MotionSample(value: value, velocity: 0)

        case .tween(let leg, let duration):
            if t < leg.start {
                return leg.previous?.sample(at: t) ?? MotionSample(value: leg.from, velocity: 0)
            }
            if duration <= 0 { return MotionSample(value: leg.to, velocity: 0) }
            let u = jsMin(1, (t - leg.start) / jsMax(duration, 1e-4))
            let value = leg.from + (leg.to - leg.from) * (1 - pow(1 - u, 3))
            let velocity = u >= 1 ? 0 : ((leg.to - leg.from) * 3 * pow(1 - u, 2)) / duration
            return MotionSample(value: value, velocity: velocity)

        case .spring(let leg, let spring):
            if t < leg.start {
                return leg.previous?.sample(at: t) ?? MotionSample(value: leg.from, velocity: 0)
            }
            let elapsed = t - leg.start
            let state = solveSpring(spring, x0: leg.from - leg.to, v0: leg.v0, t: elapsed)
            let next = MotionSample(value: leg.to + state.x, velocity: state.v)
            let blend = spring.blendDuration ?? 0
            // Written as upstream's test so a NaN blend blends (into NaN) instead of skipping.
            if blend <= 0 || elapsed >= blend { return next }
            guard let previous = leg.previous else { return next }
            let old = previous.sample(at: t)
            let u = elapsed / blend
            let w = u * u * (3 - 2 * u)
            let dw = (6 * u * (1 - u)) / blend
            return MotionSample(
                value: old.value + (next.value - old.value) * w,
                velocity: old.velocity + (next.velocity - old.velocity) * w + (next.value - old.value) * dw
            )
        }
    }
}

/// One animated number. Retargeting mid-flight starts the new spring from the current value and
/// velocity, so an interrupted expand turns into a collapse without a jump.
public struct AnimatedValue: Sendable {
    private var segment: Segment
    private let precision: Double

    /// - Parameter precision: Distance from the target (and speed) below which the value is at rest.
    public init(_ value: Double, precision: Double = 0.01) {
        segment = .rest(value)
        self.precision = precision
    }

    /// The value the motion is heading to.
    public var target: Double { segment.target }

    /// Value at `t` seconds on the island clock.
    public func value(at t: Double) -> Double { segment.sample(at: t).value }

    public func velocity(at t: Double) -> Double { segment.sample(at: t).velocity }

    /// Moves to `to`, starting at clock time `t` (seconds). `from` replaces the value and velocity
    /// the motion starts with, for a hand-off from another value.
    public mutating func set(_ to: Double, at t: Double, _ transition: Transition, from: MotionSample? = nil) {
        let delay: Double
        switch transition {
        case .instant:
            segment = .rest(to)
            return
        case .spring(_, let wait), .tween(_, let wait):
            delay = wait
        }
        let start = t + delay
        let current = segment.leg
        let pending = current.map { $0.start > t } ?? false
        // Legs planned in one call (same call time, each starting after the last) queue up.
        let queued = pending && current?.issued == t && start >= (current?.start ?? 0)
        let pendingPrevious: Segment =
            if !queued, pending, let current {
                current.previous ?? (current.issued != t ? .rest(current.from) : segment)
            } else {
                segment
            }

        let flying = pendingPrevious.sample(at: t)
        let restingAt = pendingPrevious.target
        let moving = abs(flying.value - restingAt) >= precision || abs(flying.velocity) >= precision * 10
        let handOff: MotionSample? =
            if let from, start > t, moving,
               abs(from.value - flying.value) >= precision || abs(from.velocity - flying.velocity) >= precision * 10 {
                from
            } else {
                nil
            }

        let inFlight: Segment
        if let handOff {
            let spring: SpringConfig =
                if case .spring(_, let flyingSpring) = pendingPrevious {
                    flyingSpring
                } else if case .spring(let legSpring, _) = transition {
                    legSpring
                } else if case .tween(let duration, _) = transition {
                    SpringConfig(response: jsMax(duration, 1e-3), dampingFraction: 1)
                } else {
                    SpringConfig(response: 1e-3, dampingFraction: 1)
                }
            inFlight = .spring(
                Leg(start: t, from: handOff.value, to: restingAt, v0: handOff.velocity, previous: nil, issued: t),
                spring
            )
        } else {
            inFlight = pendingPrevious
        }

        let now = handOff != nil ? inFlight.sample(at: start) : (from ?? inFlight.sample(at: start))
        if to == target, abs(now.value - to) < precision, abs(now.velocity) < precision { return }

        switch transition {
        case .instant:
            return
        case .tween(let duration, _):
            segment = .tween(
                Leg(start: start, from: now.value, to: to, v0: 0, previous: inFlight, issued: t),
                duration: duration
            )
        case .spring(let spring, _):
            let previous: Segment? =
                if let flyingLeg = inFlight.leg {
                    queued || flyingLeg.start >= t ? inFlight : inFlight.strippingPrevious
                } else {
                    nil
                }
            segment = .spring(
                Leg(start: start, from: now.value, to: to, v0: now.velocity, previous: previous, issued: t),
                spring
            )
        }
    }

    /// Whether the value has settled by clock time `t`; a settled value collapses to rest.
    public mutating func isAtRest(at t: Double) -> Bool {
        guard let leg = segment.leg else { return true }
        if t < segment.settledAfter { return false }
        let sample = segment.sample(at: t)
        let rest = abs(sample.value - leg.to) < precision && abs(sample.velocity) < precision * 10
        if rest { segment = .rest(leg.to) }
        return rest
    }
}
