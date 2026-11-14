import Foundation

/// A spring that starts after a wait. Its fields sit beside the spring's own in JSON.
public struct DelayedSpring: Sendable, Codable, Equatable {
    public var response: Double
    public var dampingFraction: Double
    public var blendDuration: Double?
    /// Seconds to wait before the spring starts.
    public var delay: Double

    public init(response: Double, dampingFraction: Double, blendDuration: Double? = nil, delay: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
        self.delay = delay
    }

    public var spring: SpringConfig {
        SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
}

/// The leading corners' own spring, and how far the trailing ones share it.
public struct CornerLead: Sendable, Codable, Equatable {
    /// The pill heights, `above` > `below`, between which the right corners blend back to `corner`.
    public struct Trailing: Sendable, Codable, Equatable {
        public var above: Double
        public var below: Double

        public init(above: Double, below: Double) {
            self.above = above
            self.below = below
        }
    }

    public var response: Double
    public var dampingFraction: Double
    public var blendDuration: Double?
    public var delay: Double
    /// Default none: the right corners keep `corner`.
    public var trailing: Trailing?

    public init(
        response: Double,
        dampingFraction: Double,
        blendDuration: Double? = nil,
        delay: Double,
        trailing: Trailing? = nil
    ) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
        self.delay = delay
        self.trailing = trailing
    }

    public var spring: SpringConfig {
        SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
}

/// How the incoming bubble's accent settles into its size from below.
public struct BubbleSettle: Sendable, Codable, Equatable {
    public var response: Double
    public var dampingFraction: Double
    public var blendDuration: Double?
    public var delay: Double
    /// The share of its size the accent is drawn smaller at the change's start, falling to 0.
    public var depth: Double

    public init(
        response: Double,
        dampingFraction: Double,
        blendDuration: Double? = nil,
        delay: Double,
        depth: Double
    ) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
        self.delay = delay
        self.depth = depth
    }

    public var spring: SpringConfig {
        SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
}

/// The pointed ends a split neck leaves at its first break.
public struct NeckTip: Sendable, Codable, Equatable {
    /// Points each nub reaches past its round cap at the break.
    public var length: Double
    /// Points of gap past the break at which the nubs are gone.
    public var reach: Double
    /// Seconds into the return after which no nub is drawn.
    public var until: Double

    public init(length: Double, reach: Double, until: Double) {
        self.length = length
        self.reach = reach
        self.until = until
    }
}

/// The width an idle island's swell leaves behind as the swell turns back.
public struct IdleWiden: Sendable, Codable, Equatable {
    /// Points the pill widens toward, both ends together.
    public var by: Double
    public var rise: SpringConfig
    /// Seconds after the swell's turn that the width lets go.
    public var hold: Double
    public var fall: SpringConfig

    public init(by: Double, rise: SpringConfig, hold: Double, fall: SpringConfig) {
        self.by = by
        self.rise = rise
        self.hold = hold
        self.fall = fall
    }
}

/// The leg that heads past the target.
public struct TailLean: Sendable, Codable, Equatable {
    public var by: Double
    public var at: Double
    public var max: Double
    public var response: Double
    public var dampingFraction: Double
    public var blendDuration: Double?

    public init(
        by: Double,
        at: Double,
        max: Double,
        response: Double,
        dampingFraction: Double,
        blendDuration: Double? = nil
    ) {
        self.by = by
        self.at = at
        self.max = max
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }

    public var spring: SpringConfig {
        SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
}

/// The leg that settles onto the target.
public struct TailSettle: Sendable, Codable, Equatable {
    public var at: Double
    public var response: Double
    public var dampingFraction: Double
    public var blendDuration: Double?

    public init(at: Double, response: Double, dampingFraction: Double, blendDuration: Double? = nil) {
        self.at = at
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }

    public var spring: SpringConfig {
        SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
}

/// The legs that end one property's motion.
public struct TailLegs: Sendable, Codable, Equatable {
    /// Heads for the target plus `by` × the travel from `at` seconds in, at most `max` past it.
    public var lean: TailLean
    /// Settles onto the target from `at` seconds after the change starts. `at` 0 skips it.
    public var settle: TailSettle

    public init(lean: TailLean, settle: TailSettle) {
        self.lean = lean
        self.settle = settle
    }
}

/// How a transition's motion ends, per property.
public struct ShapeTail: Sendable, Codable, Equatable {
    /// The pill's width, about its centre (both edges move by half).
    public var width: TailLegs
    public var height: TailLegs
    public var top: TailLegs

    public init(width: TailLegs, height: TailLegs, top: TailLegs) {
        self.width = width
        self.height = height
        self.top = top
    }
}

/// The faint wide part of iOS's content blur. A slot blurred at σ points also draws a copy blurred
/// `width` points, at weight w = min(`max`, `gain` σ ^ `power` - `floor`), added to itself
/// drawn at 1 - `dim` × w. With no weight (sharp content) no copy is drawn.
public struct BlurSkirt: Sendable, Codable, Equatable {
    /// The wide part's standard deviation in points.
    public var width: Double
    /// Its weight per point of the slot's own blur, raised to `power`.
    public var gain: Double
    /// The most weight it takes.
    public var max: Double
    /// Weight taken off, so the copy comes and goes at no weight rather than with a step.
    public var floor: Double
    /// Defaults to `gain`. The gain for a layer on its way out.
    public var exitGain: Double?
    /// Defaults to 2. The power of σ the weight follows.
    public var power: Double?
    /// Defaults to 1. How much of the weight the slot itself gives up. 0 adds the wide part on top.
    public var dim: Double?
    /// Defaults to 0. Under this blur (points on screen) the weight falls with the blur.
    public var tail: Double?

    public init(
        width: Double,
        gain: Double,
        max: Double,
        floor: Double,
        exitGain: Double? = nil,
        power: Double? = nil,
        dim: Double? = nil,
        tail: Double? = nil
    ) {
        self.width = width
        self.gain = gain
        self.max = max
        self.floor = floor
        self.exitGain = exitGain
        self.power = power
        self.dim = dim
        self.tail = tail
    }
}

/// Every spring and timing the island uses, in seconds (SwiftUI units).
public struct IslandMotion: Sendable, Codable, Equatable {
    public struct AppearWide: Sendable, Codable, Equatable {
        public var from: Double
        public var to: Double
        public var spring: SpringConfig

        public init(from: Double, to: Double, spring: SpringConfig) {
            self.from = from
            self.to = to
            self.spring = spring
        }
    }

    public struct Retarget: Sendable, Codable, Equatable {
        public var collapse: SpringConfig
        public var alertCollapse: SpringConfig

        public init(collapse: SpringConfig, alertCollapse: SpringConfig) {
            self.collapse = collapse
            self.alertCollapse = alertCollapse
        }
    }

    public struct Content: Sendable, Codable, Equatable {
        public var enter: DelayedSpring
        public var exit: DelayedSpring
        public var carryResponseMin: Double

        public init(enter: DelayedSpring, exit: DelayedSpring, carryResponseMin: Double) {
            self.enter = enter
            self.exit = exit
            self.carryResponseMin = carryResponseMin
        }
    }

    public struct Group: Sendable, Codable, Equatable {
        public var handoff: Double
        public var window: Double

        public init(handoff: Double, window: Double) {
            self.handoff = handoff
            self.window = window
        }
    }

    public struct Keyline: Sendable, Codable, Equatable {
        public var dip: Double
        public var dipAt: Double
        public var backAt: Double

        public init(dip: Double, dipAt: Double, backAt: Double) {
            self.dip = dip
            self.dipAt = dipAt
            self.backAt = backAt
        }
    }

    /// Reduced motion: shape and content crossfade over `duration`, no springs, no blur.
    public struct Reduced: Sendable, Codable, Equatable {
        public var duration: Double

        public init(duration: Double) {
            self.duration = duration
        }
    }

    public var shape: PerTransition<SpringConfig>
    /// A wide pill's appear: the edges' spring blends from `shape.appear` at `from` points of
    /// target width to `spring` at `to` and wider. Without it every appear uses `shape.appear`.
    public var appearWide: AppearWide?
    public var body: PerTransition<DelayedSpring>
    public var corner: PerTransition<DelayedSpring>
    /// The leading corners' radius on its own spring. A transition without an entry uses `corner`.
    public var cornerLead: PartialPerTransition<CornerLead>?
    public var viaIdle: PerTransition<Double>
    public var collapseLift: Double
    public var retarget: Retarget
    public var tail: PerTransition<ShapeTail>
    public var bubble: Bubble
    public var lag: PerTransition<Double>
    public var content: Content
    public var contentTiming: PerTransition<ContentMotion>
    public var press: Press
    public var longPress: Double
    public var longPressBubble: Double?
    public var alertContentDelay: Double
    public var group: Group
    public var keyline: Keyline
    public var shadowRamp: SpringConfig
    public var shadowRampPress: SpringConfig
    public var alertHold: Double
    public var alertHoldIdle: Double?
    /// Unset draws one Gaussian. The second, wide part of a content blur.
    public var blurSkirt: BlurSkirt?
    public var reduced: Reduced

    public init(
        shape: PerTransition<SpringConfig>,
        appearWide: AppearWide? = nil,
        body: PerTransition<DelayedSpring>,
        corner: PerTransition<DelayedSpring>,
        cornerLead: PartialPerTransition<CornerLead>? = nil,
        viaIdle: PerTransition<Double>,
        collapseLift: Double,
        retarget: Retarget,
        tail: PerTransition<ShapeTail>,
        bubble: Bubble,
        lag: PerTransition<Double>,
        content: Content,
        contentTiming: PerTransition<ContentMotion>,
        press: Press,
        longPress: Double,
        longPressBubble: Double? = nil,
        alertContentDelay: Double,
        group: Group,
        keyline: Keyline,
        shadowRamp: SpringConfig,
        shadowRampPress: SpringConfig,
        alertHold: Double,
        alertHoldIdle: Double? = nil,
        blurSkirt: BlurSkirt? = nil,
        reduced: Reduced
    ) {
        self.shape = shape
        self.appearWide = appearWide
        self.body = body
        self.corner = corner
        self.cornerLead = cornerLead
        self.viaIdle = viaIdle
        self.collapseLift = collapseLift
        self.retarget = retarget
        self.tail = tail
        self.bubble = bubble
        self.lag = lag
        self.content = content
        self.contentTiming = contentTiming
        self.press = press
        self.longPress = longPress
        self.longPressBubble = longPressBubble
        self.alertContentDelay = alertContentDelay
        self.group = group
        self.keyline = keyline
        self.shadowRamp = shadowRamp
        self.shadowRampPress = shadowRampPress
        self.alertHold = alertHold
        self.alertHoldIdle = alertHoldIdle
        self.blurSkirt = blurSkirt
        self.reduced = reduced
    }
}
