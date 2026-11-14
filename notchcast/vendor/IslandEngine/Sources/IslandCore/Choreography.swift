import Foundation

/// How a change plays: `spring` plays the motion, `reduced` eases, `instant` snaps.
public enum MotionMode: String, Sendable, Codable, CaseIterable {
    case spring
    case reduced
    case instant
}

/// One presentation change for the shape to move through.
public struct ShapeChange: Sendable {
    public var transition: ShapeTransition
    public var target: ShapeTarget
    /// The idle shape, which activity-swapping morphs pass through.
    public var idle: ShapeTarget
    /// Clock time in seconds the change starts at.
    public var t0: Double
    public var motion: IslandMotion
    public var mode: MotionMode

    public init(
        transition: ShapeTransition, target: ShapeTarget, idle: ShapeTarget, t0: Double,
        motion: IslandMotion, mode: MotionMode
    ) {
        self.transition = transition
        self.target = target
        self.idle = idle
        self.t0 = t0
        self.motion = motion
        self.mode = mode
    }
}

/// Which part of the island a press is on.
public enum PressedPart: String, Sendable, Codable {
    case pill
    case bubble
}

/// A long-press `swell`, or the gentle `squish` of a controlled press.
public enum PressStyle: String, Sendable, Codable {
    case swell
    case squish
}

extension IslandMotion {
    /// Content crossfade settings for a transition.
    public func contentMotion(_ transition: ShapeTransition) -> ContentMotion {
        contentTiming[transition]
    }
}

private func spring(_ config: SpringConfig, _ delay: Double = 0) -> Transition {
    .spring(config, delay: delay)
}

/// Points a tail leans past its target for a change of `travel` points: `by` of it, at most `max`.
private func leanOf(_ legs: TailLegs, _ travel: Double) -> Double {
    let by = legs.lean.by
    let sign: Double = by > 0 ? 1 : by < 0 ? -1 : 0
    return sign * min(abs(by * travel), legs.lean.max)
}

/// Queues a tail's legs: from `lean.at` toward `to + lean`, then from `settle.at` onto `to`.
private func queueTail(_ value: inout AnimatedValue, to: Double, lean: Double, legs: TailLegs, t0: Double) {
    if legs.lean.by != 0 && legs.lean.at > 0 { value.set(to + lean, at: t0, spring(legs.lean.spring, legs.lean.at)) }
    if legs.settle.at > 0 { value.set(to, at: t0, spring(legs.settle.spring, legs.settle.at)) }
}

/// A leg that starts already moving at `kick` times its travel per second; nil without a kick.
private func kicked(_ value: AnimatedValue, to: Double, t0: Double, kick: Double?) -> MotionSample? {
    guard let kick, kick != 0 else { return nil }
    let from = value.value(at: t0)
    return MotionSample(value: from, velocity: kick * (to - from))
}

/// The appear's edge spring for a pill `width` points wide, `appearWide` blended in past `from`.
private func appearEdges(_ motion: IslandMotion, width: Double) -> SpringConfig {
    let base = motion.shape[.appear]
    guard let wide = motion.appearWide, wide.to > wide.from else { return base }
    let k = min(1, max(0, (width - wide.from) / (wide.to - wide.from)))
    if k == 0 { return base }
    return SpringConfig(
        response: base.response + (wide.spring.response - base.response) * k,
        dampingFraction: base.dampingFraction + (wide.spring.dampingFraction - base.dampingFraction) * k)
}

extension ShapeAnimation {
    /// Whether a change takes a visible bubble in as its own lobe: unsplit, or a swap.
    public func absorbsBubble(transition: ShapeTransition, target: ShapeTarget, t0: Double) -> Bool {
        bubbleHeight.value(at: t0) >= 0.5 && target.bubbleHeight == 0
            && (transition == .unsplit || transition == .swap)
    }

    /// Starts the motion for one presentation change.
    public mutating func retarget(_ change: ShapeChange) {
        let kind = change.transition
        let target = change.target
        let idle = change.idle
        let t0 = change.t0
        let motion = change.motion
        let mode = change.mode
        if target.height > restHeight { restHeight = target.height }

        let opening = target.height > idle.height + 1
            && height.value(at: t0) < idle.height + 0.05 * (target.height - idle.height)
        if mode == .spring && opening {
            shadow.set(0, at: t0, .instant)
            shadow.set(1, at: t0, spring(kind == .pressExpand ? motion.shadowRampPress : motion.shadowRamp))
        } else {
            shadow.set(1, at: t0, .instant)
        }

        if mode != .spring {
            let go: Transition = mode == .instant ? .instant : .tween(duration: motion.reduced.duration)
            left.set(target.left, at: t0, go)
            right.set(target.right, at: t0, go)
            top.set(target.top, at: t0, go)
            height.set(target.height, at: t0, go)
            radius.set(target.radius, at: t0, go)
            bubbleLeft.set(target.bubbleLeft, at: t0, go)
            bubbleRight.set(target.bubbleRight, at: t0, go)
            bubbleHeight.set(target.bubbleHeight, at: t0, go)
            leadRadius.set(target.radius, at: t0, go)
            lift.set(0, at: t0, go)
            bubbleRise.set(0, at: t0, .instant)
            squish.set(0, at: t0, go)
            bubbleSquish.set(0, at: t0, go)
            widen.set(0, at: t0, go)
            return
        }

        neck = nil
        let edges = kind == .appear ? appearEdges(motion, width: target.right - target.left) : motion.shape[kind]

        let bubbleShown = bubbleHeight.value(at: t0) >= 0.5
        let absorbing = absorbsBubble(transition: kind, target: target, t0: t0)
        // A join that led this change carries on into it; any other change ends it.
        if !absorbing { joinFrom = nil }

        let via: Double
        if absorbing {
            via = kind == .swap ? (motion.bubble.absorbExpand ?? motion.viaIdle[.unsplit]) : motion.viaIdle[.unsplit]
        } else {
            via = motion.viaIdle[kind]
        }
        let turnShift = via - motion.viaIdle[kind]
        var body = motion.body[kind]
        body.delay = max(0, body.delay + (body.delay > 0 ? turnShift : 0))
        let second: SpringConfig = kind == .collapse
            ? motion.retarget.collapse
            : kind == .alertCollapse ? motion.retarget.alertCollapse : edges

        // Fold a press swell into the base values so the change carries its size and speed.
        var startLeft: MotionSample?
        var startRight: MotionSample?
        var startTop: MotionSample?
        var startHeight: MotionSample?
        var startRadius: MotionSample?
        var startLeadRadius: MotionSample?
        let squishNow = squish.value(at: t0)
        func moving(_ value: AnimatedValue) -> Bool {
            abs(value.value(at: t0)) > 1e-4 || abs(value.velocity(at: t0)) > 1e-3
        }
        if moving(squish) || moving(widen) {
            let pose = pillPose(at: t0)
            let g = 1 + squishNow * squishFactor
            startLeft = pose.left
            startRight = pose.right
            startTop = pose.top
            startHeight = pose.height
            startRadius = MotionSample(value: radius.value(at: t0) * g, velocity: radius.velocity(at: t0) * g)
            startLeadRadius = MotionSample(
                value: leadRadius.value(at: t0) * g, velocity: leadRadius.velocity(at: t0) * g)
            squish.set(0, at: t0, .instant)
            widen.set(0, at: t0, .instant)
        }

        var bubbleStartLeft: MotionSample?
        var bubbleStartRight: MotionSample?
        var bubbleStartHeight: MotionSample?
        let bubbleSquishNow = bubbleSquish.value(at: t0)
        if abs(bubbleSquishNow) > 1e-4 || abs(bubbleSquish.velocity(at: t0)) > 1e-3 {
            let pose = bubblePose(at: t0)
            bubbleStartLeft = pose.left
            bubbleStartRight = pose.right
            bubbleStartHeight = pose.height
            bubbleSquish.set(0, at: t0, .instant)
        }

        if bubbleShown && target.bubbleHeight == 0 && !absorbing {
            let bubbleRightNow = bubbleRight.value(at: t0)
            if bubbleRightNow > right.value(at: t0) {
                startRight = MotionSample(value: bubbleRightNow, velocity: bubbleRight.velocity(at: t0))
            }
            bubbleHeight.set(0, at: t0, .instant)
        }

        func edge(_ value: inout AnimatedValue, _ to: Double, _ idleTo: Double, _ from: MotionSample? = nil) {
            if via > 0 {
                value.set(idleTo, at: t0, spring(edges), from: from)
                value.set(to, at: t0, spring(second, via))
            } else {
                value.set(to, at: t0, spring(edges), from: from)
            }
        }
        let ownEdges = kind == .collapseSplit && target.bubbleHeight > 0
        if ownEdges {
            let spread = motion.bubble.collapseSplitSpread
            let split = motion.bubble.collapseSplitVia
            let wide = target.left - spread.left
            let leftFrom = startLeft ?? kicked(left, to: wide, t0: t0, kick: spread.kick)
            left.set(wide, at: t0, spring(edges), from: leftFrom)
            left.set(target.left, at: t0, spring(spread.spring, spread.at))
            // The right side shrinks with the bubble as one blob, then pulls back to pinch it off.
            right.set(target.bubbleRight - split.dip, at: t0, spring(split.down), from: startRight)
            if spread.right != 0 {
                let peel = spread.rightPeel
                if peel.at < spread.rightSettle.at {
                    right.set(target.right + peel.to, at: t0, spring(peel.spring, peel.at))
                }
                right.set(target.right + spread.right, at: t0, spring(spread.rightSettle.spring, spread.rightSettle.at))
                right.set(target.right, at: t0, spring(spread.rightBack.spring, spread.rightBack.at))
            } else {
                right.set(target.right, at: t0, spring(edges, split.at))
            }
            neck = Neck(
                gap: spread.neckGap, power: spread.neckPower,
                tip: spread.neckTip.map { Neck.Tip(length: $0.length, reach: $0.reach, until: t0 + $0.until) })
        } else {
            edge(&left, target.left, idle.left, startLeft)
            edge(&right, target.right, idle.right, startRight)
        }

        height.set(target.height, at: t0, spring(body.spring, body.delay), from: startHeight)
        let absorbCorner = absorbing && kind == .swap ? motion.bubble.absorbExpandCorner : nil
        let corner = absorbCorner ?? motion.corner[kind]
        let cornerDelay: Double
        if let absorbCorner {
            cornerDelay = max(0, via + absorbCorner.delay)
        } else {
            cornerDelay = corner.delay > 0 ? max(0, corner.delay + turnShift) : 0
        }
        radius.set(target.radius, at: t0, spring(corner.spring, cornerDelay), from: startRadius)
        let lead = absorbCorner == nil ? motion.cornerLead?[kind] : nil
        let leadDelay = lead.map { $0.delay > 0 ? max(0, $0.delay + turnShift) : 0 } ?? cornerDelay
        leadRadius.set(target.radius, at: t0, spring(lead?.spring ?? corner.spring, leadDelay), from: startLeadRadius)
        if let trailing = lead?.trailing { cornerTrail = CornerTrail(above: trailing.above, below: trailing.below) }
        if (kind == .collapse || kind == .alertCollapse) && via > 0 {
            top.set(target.top - motion.collapseLift, at: t0, spring(body.spring), from: startTop)
            top.set(target.top, at: t0, spring(second, via))
        } else {
            top.set(target.top, at: t0, spring(body.spring, body.delay), from: startTop)
        }

        // The tail's lean and settle queue after the legs above; the split's edges have their own.
        let tail = motion.tail[kind]
        let width0 = (startRight?.value ?? right.value(at: t0)) - (startLeft?.value ?? left.value(at: t0))
        let height0 = startHeight?.value ?? height.value(at: t0)
        let top0 = startTop?.value ?? top.value(at: t0)
        if !ownEdges {
            let lean = leanOf(tail.width, target.right - target.left - width0)
            queueTail(&left, to: target.left, lean: -lean / 2, legs: tail.width, t0: t0)
            queueTail(&right, to: target.right, lean: lean / 2, legs: tail.width, t0: t0)
        }
        queueTail(&height, to: target.height, lean: leanOf(tail.height, target.height - height0), legs: tail.height, t0: t0)
        queueTail(&top, to: target.top, lean: leanOf(tail.top, target.top - top0), legs: tail.top, t0: t0)
        if ownEdges {
            let rise = motion.bubble.collapseSplitLift
            lift.set(rise.by, at: t0, spring(rise.spring))
            lift.set(0, at: t0, spring(rise.back.spring, rise.back.at))
        } else {
            lift.set(0, at: t0, spring(body.spring))
        }

        if !(ownEdges && !bubbleShown) && bubbleRise.target != 0 {
            bubbleRise.set(0, at: t0, .instant)
        }
        if target.bubbleHeight > 0 && !bubbleShown {
            // The bubble grows out of the pill's end; its left edge springing out is the pinch-off.
            let bubble = kind == .collapseSplit ? motion.bubble.collapseSplit : motion.bubble.split
            let h = target.bubbleHeight
            bubbleHeight.set(h, at: t0, .instant)
            bubbleLeft.set(target.right - h, at: t0, .instant)
            bubbleRight.set(startRight?.value ?? right.value(at: t0), at: t0, .instant)
            if kind == .collapseSplit {
                let split = motion.bubble.collapseSplitVia
                bubbleRight.set(target.bubbleRight - split.dip, at: t0, spring(split.down))
                bubbleRight.set(target.bubbleRight, at: t0, spring(split.spring, split.at))
                let rise = motion.bubble.collapseSplitRise
                bubbleRise.set(0, at: t0, .instant)
                bubbleRise.set(1, at: t0, spring(rise.spring, rise.delay))
                let from = motion.bubble.collapseSplitSpread.bubbleFrom
                bubbleLeft.set(target.bubbleLeft - from, at: t0, .instant)
                if from != 0 { bubbleLeft.set(target.bubbleLeft, at: t0, spring(bubble.spring, bubble.delay)) }
            } else {
                edge(&bubbleRight, target.bubbleRight, idle.right)
                bubbleLeft.set(target.bubbleLeft, at: t0, spring(bubble.spring, bubble.delay))
            }
        } else if target.bubbleHeight > 0 {
            bubbleLeft.set(target.bubbleLeft, at: t0, spring(edges))
            bubbleRight.set(target.bubbleRight, at: t0, spring(edges))
            bubbleHeight.set(target.bubbleHeight, at: t0, spring(edges))
        } else if absorbing {
            // The bubble slides under the sensor as its own lobe and is gone as the shape turns.
            let rest = bubbleHeight.value(at: t0)
            if let swollen = bubbleStartHeight {
                bubbleHeight.set(swollen.value, at: t0, .instant)
                bubbleHeight.set(rest, at: t0, spring(motion.bubble.unsplit))
            }
            bubbleLeft.set(idle.right - rest, at: t0, spring(motion.bubble.unsplit), from: bubbleStartLeft)
            bubbleRight.set(idle.right, at: t0, spring(motion.bubble.unsplitSlide), from: bubbleStartRight)
            let absorbAt = kind == .unsplit || via <= 0 ? motion.bubble.unsplitAbsorb : via
            // A step, not a short tween: a frame inside a tiny tween drew the lobe as a thin bar.
            bubbleHeight.set(0, at: t0, .tween(duration: 0, delay: absorbAt))
        } else {
            bubbleLeft.set(target.bubbleLeft, at: t0, .instant)
            bubbleRight.set(target.bubbleRight, at: t0, .instant)
            bubbleHeight.set(0, at: t0, .instant)
        }
    }

    /// Starts a bubble's join ahead of the change that takes it in; a nil `joinAt` undoes it.
    public mutating func leadJoin(
        joinAt: Double?, at t: Double, idleRight: Double, restLeft: Double, motion: IslandMotion, mode: MotionMode
    ) {
        let lead = motion.bubble.joinLead ?? 0
        if mode != .spring || lead <= 0 { return }
        // Once the shape has left the split, the change that took the bubble in runs the join.
        if bubbleHeight.target == 0 { return }
        let unsplit = motion.bubble.unsplit
        guard let joinAt else {
            if joinFrom == nil { return }
            joinFrom = nil
            bubbleLeft.set(restLeft, at: t, spring(unsplit))
            return
        }
        let from = max(t, joinAt - lead)
        joinFrom = from
        bubbleLeft.set(idleRight - bubbleHeight.target, at: t, spring(unsplit, from - t))
    }

    /// The press: a long-press swells the pressed part about its centre, a controlled one squishes.
    public mutating func retargetPress(
        pressed: PressedPart?, style: PressStyle, at t: Double, motion: IslandMotion, metrics: IslandMetrics,
        mode: MotionMode, idle: Bool = false
    ) {
        if pressed != nil { squishFactor = style == .swell ? metrics.press.swell : metrics.press.squish }
        // A swelling bubble closes the gap with no neck; they join only when a change absorbs it.
        if pressed == .bubble { neck = Neck(gap: 0.01, power: 1.5) }
        func go(_ config: SpringConfig) -> Transition {
            switch mode {
            case .instant: .instant
            case .reduced: .tween(duration: motion.reduced.duration)
            case .spring: spring(config)
            }
        }
        let down = style == .swell ? motion.press.swell : motion.press.down
        let idleRelease = style == .swell && idle ? motion.press.idleRelease : nil
        let up = idleRelease?.spring ?? (style == .swell ? motion.press.release : motion.press.up)
        let bubbleDown = style == .swell ? (motion.press.bubbleSwell ?? down) : down
        let bubbleTo = style == .swell && squishFactor > 0
            ? (metrics.press.bubbleSwell ?? metrics.press.swell) / squishFactor
            : 1
        let parts: [(PressedPart, WritableKeyPath<ShapeAnimation, AnimatedValue>)] = [
            (.pill, \.squish), (.bubble, \.bubbleSquish),
        ]
        for (part, key) in parts {
            let on = pressed == part
            // Leave a part that is already where it should be alone, so it stays at rest.
            if !on && self[keyPath: key].target == 0 && self[keyPath: key].isAtRest(at: t) { continue }
            let bubble = part == .bubble
            var from: MotionSample?
            if !on, let idleRelease, mode == .spring {
                let value = self[keyPath: key]
                from = MotionSample(value: value.value(at: t), velocity: value.velocity(at: t) * idleRelease.carry)
            }
            self[keyPath: key].set(on ? (bubble ? bubbleTo : 1) : 0, at: t, go(on ? (bubble ? bubbleDown : down) : up), from: from)
            // An idle pill's width runs on as its swell turns back, then lets go `hold` later.
            if !on && !bubble && idleRelease != nil && mode == .spring, let widening = motion.press.idleWiden {
                widen.set(widening.by, at: t, spring(widening.rise))
                widen.set(0, at: t, spring(widening.fall, widening.hold))
            }
        }
    }
}
