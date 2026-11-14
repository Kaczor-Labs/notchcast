import Foundation

/// A content slot the stage draws, named as upstream's `data-slot`.
public enum SlotName: String, CaseIterable, Codable, Sendable {
    case root
    case leading
    case trailing
    case attached
    case detached
    case splitAttachedLeading
    case splitAttachedTrailing
    case splitDetachedLeading
    case splitDetachedTrailing
    case expanded
    case expandedClip
    case expandedInner
    case expandedLeading
    case expandedCenter
    case expandedTrailing
    case expandedBottom
}

/// The expanded slots that hold a region, paired with that region.
let regionSlots: [(SlotName, ExpandedRegion)] = [
    (.expandedLeading, .leading),
    (.expandedCenter, .center),
    (.expandedTrailing, .trailing),
    (.expandedBottom, .bottom),
]

/// One slot's drawn numbers before they are written. Fields a slot does not use stay 0.
public struct SlotDraw: Sendable, Equatable {
    public var opacity: Double
    /// The filter's blur in points, before the slot's own scale.
    public var blur: Double
    public var x: Double
    public var y: Double
    /// Scale across, with any stretch.
    public var sx: Double
    public var sy: Double
    /// How far an expanded region is drawn above its place.
    public var lift: Double
    /// How far the expanded clip follows the content.
    public var follow: Double
    /// A bubble slot's band top and bottom on screen.
    public var bandTop: Double
    public var bandBottom: Double
    /// The centre of a bubble band's cap; 0 is no cap.
    public var cap: Double
    /// The weight of the blur's wide part: the slot draws at 1 - this and its copy at this.
    public var skirt: Double

    /// A draw with every field set.
    public init(
        opacity: Double = 0, blur: Double = 0, x: Double = 0, y: Double = 0, sx: Double = 0, sy: Double = 0,
        lift: Double = 0, follow: Double = 0, bandTop: Double = 0, bandBottom: Double = 0, cap: Double = 0,
        skirt: Double = 0
    ) {
        self.opacity = opacity
        self.blur = blur
        self.x = x
        self.y = y
        self.sx = sx
        self.sy = sy
        self.lift = lift
        self.follow = follow
        self.bandTop = bandTop
        self.bandBottom = bandBottom
        self.cap = cap
        self.skirt = skirt
    }

    /// Every field, in upstream's order.
    static var fields: [WritableKeyPath<SlotDraw, Double>] {
        [\.opacity, \.blur, \.x, \.y, \.sx, \.sy, \.lift, \.follow, \.bandTop, \.bandBottom, \.cap, \.skirt]
    }

    /// The smallest difference per field worth carrying, in `fields` order.
    static let carryFloor = SlotDraw(
        opacity: 5e-4, blur: 5e-3, x: 5e-3, y: 5e-3, sx: 1e-5, sy: 1e-5, lift: 5e-3, follow: 1e-4,
        bandTop: 5e-3, bandBottom: 5e-3, cap: 5e-3, skirt: 5e-4)
}

/// One slot's carry: the offset and speed it resolves from, and an exit's opacity multiplier.
struct SlotCarry: Sendable, Equatable {
    var delta: SlotDraw
    var speed: SlotDraw?
    var ratio: Double?
}

/// What a layer drew at an interruption less what its new look draws, resolving to nothing.
struct Carry: Sendable {
    var weight: AnimatedValue
    /// Clock time (s) of the change.
    var at: Double
    /// The resolving spring's angular frequency.
    var omega: Double
    var slots: [SlotName: SlotCarry]
}

/// What a layer draws, for a carry: whether it shows, its slots, and its band cap's travel.
struct LayerDraw: Sendable, Equatable {
    var shown: Bool
    var slots: [SlotName: SlotDraw]
    var capTravel: Double?
}

/// Seconds between the samples a carry's speed is measured from.
let speedStep = 1e-3

/// The carry resolves critically damped, so no value passes where it is going.
let carryDamping = 1.0

/// How much of a carried speed is left at `t`: τ·e^(−ωτ), τ from the change.
func carryLag(_ carry: Carry, _ t: Double) -> Double {
    let tau = t - carry.at
    return tau > 0 ? tau * exp(-carry.omega * tau) : 0
}

/// `base` with the carry's delta added at `weight` and its speed at `lag`.
func addCarry(_ base: SlotDraw, _ carried: SlotCarry, weight: Double, lag: Double) -> SlotDraw {
    let delta = carried.delta
    let speed = carried.speed
    func at(_ field: KeyPath<SlotDraw, Double>) -> Double {
        base[keyPath: field] + delta[keyPath: field] * weight + (speed.map { $0[keyPath: field] * lag } ?? 0)
    }
    let opacity: Double
    if let ratio = carried.ratio {
        opacity = base.opacity * max(0, 1 + (ratio - 1) * weight + (speed.map { $0.opacity * lag } ?? 0))
    } else {
        opacity = at(\.opacity)
    }
    return SlotDraw(
        opacity: clamp01(opacity),
        blur: max(0, at(\.blur)),
        x: at(\.x),
        y: at(\.y),
        sx: at(\.sx),
        sy: at(\.sy),
        lift: at(\.lift),
        follow: at(\.follow),
        bandTop: at(\.bandTop),
        bandBottom: at(\.bandBottom),
        // A cap of 0 is no cap: it is only carried between two caps.
        cap: base.cap == 0 ? 0 : at(\.cap),
        skirt: clamp01(at(\.skirt)))
}

/// What `was` drew less what `now` draws, or nil when no field differs past the carry floor.
func carryOf(_ was: SlotDraw, _ now: SlotDraw) -> SlotDraw? {
    var delta = SlotDraw()
    var moved = false
    for field in SlotDraw.fields {
        // A band gaining or losing its cap has no distance between the two to carry.
        let value = field == \SlotDraw.cap && (was.cap == 0 || now.cap == 0)
            ? 0 : was[keyPath: field] - now[keyPath: field]
        delta[keyPath: field] = value
        if abs(value) > SlotDraw.carryFloor[keyPath: field] { moved = true }
    }
    return moved ? delta : nil
}

/// Each field's speed at `first` from three samples a step apart; `sign` 1 looks back, -1 ahead.
func speedOf(_ first: SlotDraw, _ second: SlotDraw, _ third: SlotDraw, sign: Double) -> SlotDraw {
    var out = SlotDraw()
    for field in SlotDraw.fields {
        let near = (sign * (first[keyPath: field] - second[keyPath: field])) / speedStep
        let far = (sign * (second[keyPath: field] - third[keyPath: field])) / speedStep
        let smooth = abs(near - far)
            <= 0.2 * max(abs(near), abs(far)) + SlotDraw.carryFloor[keyPath: field] / speedStep
        out[keyPath: field] = smooth ? 1.5 * near - 0.5 * far : 0
    }
    return out
}
