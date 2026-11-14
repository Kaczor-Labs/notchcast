import Foundation

/// The animated numbers behind the shape. One spring per property.
public struct ShapeAnimation: Sendable {
    /// Where the split's neck breaks for the motion under way, and how it thins.
    public struct Neck: Sendable, Equatable {
        /// Pointed nubs the neck's first break leaves, drawn until the clock time `until`.
        public struct Tip: Sendable, Equatable {
            public var length: Double
            public var reach: Double
            public var until: Double

            public init(length: Double, reach: Double, until: Double) {
                self.length = length
                self.reach = reach
                self.until = until
            }
        }

        public var gap: Double
        public var power: Double
        public var tip: Tip?

        public init(gap: Double, power: Double, tip: Tip? = nil) {
            self.gap = gap
            self.power = power
            self.tip = tip
        }
    }

    /// Pill heights between which the right corners blend from `leadRadius` back to `radius`.
    public struct CornerTrail: Sendable, Equatable {
        public var above: Double
        public var below: Double

        public init(above: Double, below: Double) {
            self.above = above
            self.below = below
        }
    }

    public var left: AnimatedValue
    public var right: AnimatedValue
    public var top: AnimatedValue
    public var height: AnimatedValue
    public var radius: AnimatedValue
    /// The two left corners' radius. It moves with `radius` unless the transition has its own.
    public var leadRadius: AnimatedValue
    public var bubbleLeft: AnimatedValue
    public var bubbleRight: AnimatedValue
    public var bubbleHeight: AnimatedValue
    /// 0 centres the bubble on the pill's height, 1 puts it at the pill's top.
    public var bubbleRise: AnimatedValue
    /// Points the attached pill rides above `top`, the bubble staying put.
    public var lift: AnimatedValue
    /// 0 at rest, 1 fully pressed. Scales the pill about its centre by `squishFactor`.
    public var squish: AnimatedValue
    /// The same for the detached bubble, pressed on its own.
    public var bubbleSquish: AnimatedValue
    /// Points the pill is drawn wider than its edges and swell put it, about its centre.
    public var widen: AnimatedValue
    /// How far the expanded shadow has come in, 0 to 1.
    public var shadow: AnimatedValue
    /// How much a full `squish` grows the pill.
    public var squishFactor: Double
    /// Height of the expanded shape at rest, which the shadow's strength is measured against.
    public var restHeight: Double
    /// nil uses `metrics.bridge`.
    public var neck: Neck?
    /// From this clock time the neck is drawn as in a merge, whatever `neck` says.
    public var joinFrom: Double?
    /// Kept until another change sets its own, so an interrupted return carries on blending.
    public var cornerTrail: CornerTrail?

    /// A shape at rest on `target`.
    public init(target: ShapeTarget, metrics: IslandMetrics) {
        left = AnimatedValue(target.left)
        right = AnimatedValue(target.right)
        top = AnimatedValue(target.top)
        height = AnimatedValue(target.height)
        radius = AnimatedValue(target.radius)
        leadRadius = AnimatedValue(target.radius)
        bubbleLeft = AnimatedValue(target.bubbleLeft)
        bubbleRight = AnimatedValue(target.bubbleRight)
        bubbleHeight = AnimatedValue(target.bubbleHeight)
        bubbleRise = AnimatedValue(0)
        lift = AnimatedValue(0)
        squish = AnimatedValue(0, precision: 0.001)
        bubbleSquish = AnimatedValue(0, precision: 0.001)
        widen = AnimatedValue(0, precision: 0.001)
        shadow = AnimatedValue(1, precision: 0.001)
        squishFactor = metrics.press.swell
        restHeight = metrics.expanded.minHeight
        neck = nil
        joinFrom = nil
        cornerTrail = nil
    }

    /// Whether every property has settled at `t`. Each settled value collapses to static.
    public mutating func isAtRest(at t: Double) -> Bool {
        let keys: [WritableKeyPath<ShapeAnimation, AnimatedValue>] = [
            \.left, \.right, \.top, \.height, \.radius, \.leadRadius, \.bubbleLeft, \.bubbleRight,
            \.bubbleHeight, \.bubbleRise, \.lift, \.squish, \.bubbleSquish, \.widen, \.shadow,
        ]
        var rest = true
        for key in keys {
            rest = self[keyPath: key].isAtRest(at: t) && rest
        }
        return rest
    }
}

/// The pill's drawn edges with the squish applied, and their velocities.
public struct PillPose: Sendable, Equatable {
    public var left: MotionSample
    public var right: MotionSample
    public var height: MotionSample
    public var top: MotionSample
}

/// The bubble's edges with its swell applied, and their velocities, from the centre line.
public struct BubblePose: Sendable, Equatable {
    public var left: MotionSample
    public var right: MotionSample
    public var height: MotionSample
}

/// One drawn frame, in stage coordinates (x from the stage's left edge, y from its top).
public struct FrameGeometry: Sendable, Equatable {
    /// A pill box. `radius` is the right corners', `lead` the left corners'.
    public struct Box: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var radius: Double
        public var lead: Double
    }

    /// The detached capsule. Width 0 while too small to draw; `span` is its width either way.
    public struct Bubble: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var span: Double
        public var scale: Double
    }

    /// The outlines. `clip` caps its corner radius for content; `outline` keeps the island's own.
    public struct Paths: Sendable, Equatable {
        public var pill: IslandPath
        public var bubble: IslandPath
        public var bridge: IslandPath
        public var clip: IslandPath
        public var outline: IslandPath
        public var bubbleClip: IslandPath
    }

    public var pill: Box
    /// The pill as drawn: inset by the shadow's pull, its corner capped to fit.
    public var drawn: Box
    public var bubble: Bubble
    public var paths: Paths
    /// 0 at capsule height, 1 at the expanded shape's resting height.
    public var expansion: Double
    /// The expanded shadow's strength, 0 to 1.
    public var shadow: Double
}

private func sample(_ value: AnimatedValue, _ t: Double) -> MotionSample {
    MotionSample(value: value.value(at: t), velocity: value.velocity(at: t))
}

private func smoothstep(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c * c * (3 - 2 * c)
}

private func joined(_ a: IslandPath, _ b: IslandPath) -> IslandPath {
    IslandPath(a.elements + b.elements)
}

extension ShapeAnimation {
    /// The pill's drawn edges at `t`, with the squish applied, and their velocities.
    public func pillPose(at t: Double) -> PillPose {
        let left = sample(self.left, t)
        let right = sample(self.right, t)
        let top = sample(self.top, t)
        let height = sample(self.height, t)
        let squish = sample(self.squish, t)
        let widen = sample(self.widen, t)
        let g = 1 + squish.value * squishFactor
        let dg = squish.velocity * squishFactor
        let cx = (left.value + right.value) / 2
        let dcx = (left.velocity + right.velocity) / 2
        let w = max(0, right.value - left.value)
        let dw = right.velocity - left.velocity
        let h = max(0, height.value)
        let half = (w * g + widen.value) / 2
        let dHalf = (dw * g + w * dg + widen.velocity) / 2
        return PillPose(
            left: MotionSample(value: cx - half, velocity: dcx - dHalf),
            right: MotionSample(value: cx + half, velocity: dcx + dHalf),
            height: MotionSample(value: h * g, velocity: height.velocity * g + h * dg),
            top: MotionSample(
                value: top.value - (h * (g - 1)) / 2,
                velocity: top.velocity - (height.velocity * (g - 1) + h * dg) / 2)
        )
    }

    /// The bubble's edges at `t` with its swell applied, and their velocities.
    public func bubblePose(at t: Double) -> BubblePose {
        let left = sample(bubbleLeft, t)
        let right = sample(bubbleRight, t)
        let height = sample(bubbleHeight, t)
        let squish = sample(bubbleSquish, t)
        let g = 1 + squish.value * squishFactor
        let dg = squish.velocity * squishFactor
        let cx = (left.value + right.value) / 2
        let dcx = (left.velocity + right.velocity) / 2
        let w = max(0, right.value - left.value)
        let dw = right.velocity - left.velocity
        return BubblePose(
            left: MotionSample(value: cx - (w * g) / 2, velocity: dcx - (dw * g + w * dg) / 2),
            right: MotionSample(value: cx + (w * g) / 2, velocity: dcx + (dw * g + w * dg) / 2),
            height: MotionSample(value: height.value * g, velocity: height.velocity * g + height.value * dg)
        )
    }

    /// Where the bubble sits at `t` before its swell, in stage coordinates.
    private func bubbleBase(at t: Double, stageWidth: Double) -> (left: Double, top: Double, width: Double, height: Double) {
        let height = max(0, bubbleHeight.value(at: t))
        let left = stageWidth / 2 + bubbleLeft.value(at: t)
        let width = max(height, stageWidth / 2 + bubbleRight.value(at: t) - left)
        // Level with the pill's middle, so a tall pill hides it in its side until it rises.
        let rise = min(1, max(0, bubbleRise.value(at: t)))
        let pillHeight = self.height.value(at: t)
        let top = self.top.value(at: t) + (pillHeight - height) / 2 * (1 - rise)
        return (left, top, width, height)
    }

    /// Pose of the shape at time `t` (seconds), laid out on a stage `stageWidth` wide.
    public func frame(at t: Double, stageWidth: Double, metrics: IslandMetrics) -> FrameGeometry {
        let pose = pillPose(at: t)
        let width = max(0, pose.right.value - pose.left.value)
        let h = max(0, pose.height.value)
        let x = stageWidth / 2 + pose.left.value
        let y = pose.top.value - lift.value(at: t)
        let g = 1 + squish.value(at: t) * squishFactor
        let lead = max(0, min(leadRadius.value(at: t) * g, h / 2, width / 2))
        let own = max(0, min(radius.value(at: t) * g, h / 2, width / 2))
        var share = 0.0
        if let trail = cornerTrail, lead != own {
            share = smoothstep((h - trail.below) / max(1e-6, trail.above - trail.below))
        }
        let radius = share > 0 ? own + (lead - own) * share : own

        // A swollen compact pill casts no shadow, so the swell is divided back out.
        let capsuleHeight = metrics.compact.height
        let expansion = min(1, max(0, (h / g - capsuleHeight) / max(1, restHeight - capsuleHeight)))

        let base = bubbleBase(at: t, stageWidth: stageWidth)
        let gb = 1 + bubbleSquish.value(at: t) * squishFactor
        let bh = base.height * gb
        let bw = base.width * gb
        let bl = base.left - (base.width * (gb - 1)) / 2
        let by = base.top - (base.height * (gb - 1)) / 2

        let e = metrics.expanded
        func superCorner(_ r: Double) -> CornerShape {
            CornerShape(
                rx: min(width / 2, r * (1 + (e.cornerAspect - 1) * expansion)),
                ry: r,
                exponent: 2 + (e.cornerExponent - 2) * expansion)
        }
        let pull = e.shadow.pull
        let k = pull.opacity > 0 ? (expansion * e.shadow.opacity) / pull.opacity : 0
        let dx = pull.side * k
        let dy = pull.top * k
        let dw = max(0, width - 2 * dx)
        let dh = max(0, h - (pull.top + pull.bottom) * k)
        let smoothing = metrics.corner.smoothing
        let pill = smoothing > 0
            ? IslandPath.continuousRect(
                x: x + dx, y: y + dy, width: dw, height: dh, radius: min(radius, dh / 2, dw / 2),
                smoothing: smoothing, leading: min(lead, dh / 2, dw / 2))
            : IslandPath.roundedRect(
                x: x + dx, y: y + dy, width: dw, height: dh, corner: superCorner(radius),
                leading: lead == radius ? nil : superCorner(lead))
        let showBubble = bh >= 0.5
        let neck = joinFrom.map { t >= $0 } == true ? nil : self.neck
        let bubble = showBubble ? IslandPath.capsule(x: bl, y: by, width: bw, height: bh, smoothing: smoothing) : IslandPath()
        // Overlapping caps read as one two-lobe blob while the pill is still capsule-sized.
        let capsules = showBubble && h <= metrics.minimal.height * 1.25
        let pillCap = Circle(x: x + width - h / 2, y: y + h / 2, r: h / 2)
        let bubbleCap = Circle(x: bl + bh / 2, y: by + bh / 2, r: bh / 2)
        let maxGap = neck?.gap ?? metrics.bridge.maxGap
        let neckPath = capsules
            ? IslandPath.bridge(
                pillCap, bubbleCap,
                BridgeOptions(
                    handleSize: metrics.bridge.handleSize, spread: metrics.bridge.spread, maxGap: maxGap,
                    power: neck?.power ?? 1.5))
            : IslandPath()
        var nubs = IslandPath()
        if capsules, neckPath.isEmpty, let tip = neck?.tip, t < tip.until, tip.reach > 0 {
            let gap = hypot(bubbleCap.x - pillCap.x, bubbleCap.y - pillCap.y) - pillCap.r - bubbleCap.r
            let length = tip.length * min(1, max(0, 1 - (gap - maxGap) / tip.reach))
            if gap >= 0 && length > 0 {
                nubs = joined(
                    IslandPath.cusp(pillCap, toward: Vec(x: bubbleCap.x, y: bubbleCap.y), length: length),
                    IslandPath.cusp(bubbleCap, toward: Vec(x: pillCap.x, y: pillCap.y), length: length))
            }
        }
        let bridge = neckPath.isEmpty ? nubs : neckPath
        let chamfer = metrics.contentClip.chamfer
        let clipRadius = metrics.contentClip.radius
        func clipOf(
            _ cx: Double, _ cy: Double, _ cw: Double, _ ch: Double, _ r: Double, _ cap: Double, _ leading: Double? = nil
        ) -> IslandPath {
            let rl = leading ?? r
            if chamfer > 0 && cap == clipRadius { return .chamfer(x: cx, y: cy, width: cw, height: ch, leg: r * chamfer) }
            // Concentric with the island and capped: big corners clip content, capsules don't.
            let inset = max(0, r - cap)
            let rc = min(r, cap)
            let corner = CornerShape(rx: rc, ry: rc, exponent: 2)
            if rl == r {
                return .roundedRect(
                    x: cx + inset, y: cy + inset, width: max(0, cw - 2 * inset), height: max(0, ch - 2 * inset),
                    corner: corner)
            }
            // Top and bottom take the smaller inset, so no side is cut past its own corner.
            let insetL = max(0, rl - cap)
            let v = min(inset, insetL)
            let rcl = min(rl, cap)
            return .roundedRect(
                x: cx + insetL, y: cy + v, width: max(0, cw - inset - insetL), height: max(0, ch - 2 * v),
                corner: corner, leading: CornerShape(rx: rcl, ry: rcl, exponent: 2))
        }
        let bubbleClip = showBubble ? clipOf(bl, by, bw, bh, bh / 2, clipRadius) : IslandPath()
        let clip = joined(clipOf(x, y, width, h, radius, clipRadius, lead), bubbleClip)
        let outline = joined(
            clipOf(x, y, width, h, radius, .infinity, lead),
            showBubble ? clipOf(bl, by, bw, bh, bh / 2, .infinity) : IslandPath())

        let drawnRadius = min(radius, dh / 2, dw / 2)
        let drawnLead = min(lead, dh / 2, dw / 2)
        return FrameGeometry(
            pill: FrameGeometry.Box(x: x, y: y, width: width, height: h, radius: radius, lead: lead),
            drawn: FrameGeometry.Box(x: x + dx, y: y + dy, width: dw, height: dh, radius: drawnRadius, lead: drawnLead),
            bubble: FrameGeometry.Bubble(x: bl, y: by, width: showBubble ? bw : 0, height: bh, span: bw, scale: gb),
            paths: FrameGeometry.Paths(
                pill: pill, bubble: bubble, bridge: bridge, clip: clip, outline: outline, bubbleClip: bubbleClip),
            expansion: expansion,
            shadow: min(expansion, max(0, shadow.value(at: t)))
        )
    }
}

/// The pill's content clip for content laid out for a resting box and drawn into the current box.
/// At `follow` 0 it is the live clip; at 1 the resting clip mapped onto the box as the content is.
public func followingClip(
    x: Double, y: Double, width: Double, height: Double, radius: Double,
    restWidth: Double, restHeight: Double, restRadius: Double, cap: Double, follow: Double
) -> IslandPath {
    let sx = restWidth > 0.5 ? width / restWidth : 1
    let sy = restHeight > 0.5 ? height / restHeight : 1
    let liveInset = max(0, radius - cap)
    let liveRadius = min(radius, cap)
    // At rest the mapped clip is the live one, drawn by the same call so it matches to the bit.
    let still = abs(sx - 1) < 1e-9 && abs(sy - 1) < 1e-9 && abs(radius - restRadius) < 1e-9
    if follow <= 0 || still {
        return .roundedRect(
            x: x + liveInset, y: y + liveInset,
            width: max(0, width - 2 * liveInset), height: max(0, height - 2 * liveInset),
            corner: CornerShape(rx: liveRadius, ry: liveRadius, exponent: 2))
    }
    let restInset = max(0, restRadius - cap)
    let restCorner = min(restRadius, cap)
    func mix(_ a: Double, _ b: Double) -> Double { follow >= 1 ? b : a + (b - a) * follow }
    let ix = mix(liveInset, restInset * sx)
    let iy = mix(liveInset, restInset * sy)
    return .roundedRect(
        x: x + ix, y: y + iy, width: max(0, width - 2 * ix), height: max(0, height - 2 * iy),
        corner: CornerShape(
            rx: max(0, mix(liveRadius, restCorner * sx)), ry: max(0, mix(liveRadius, restCorner * sy)), exponent: 2))
}
