import Foundation

extension ContentStage {
    /// The upstream retarget: measures, moves the shape, and starts the content's presences.
    mutating func place(_ scene: ContentScene, _ raw: ContentMeasures, now: Double) -> Bool {
        shapeTransition = nil
        let changedAt = now
        let keyChanging = last.key != nil && !sameString(last.key, scene.key)
        let shownBefore = keyChanging
            ? [sample(changedAt, carried: true), sample(changedAt - speedStep * 1000, carried: true),
                sample(changedAt - 2 * speedStep * 1000, carried: true)] : nil
        let measure = measured(scene, raw)
        let width = islandScreenWidth(containerWidth: stageWidth, metrics: metrics)
        let target = ShapeTarget(scene.kind, measure: measure, screenWidth: width, metrics: metrics)
        let prev = last
        let first = prev.key == nil
        let keyChanged = !sameString(prev.key, scene.key)
        let change = scene.change
        let changeStamped = change != nil && change!.id != prev.changeId
        let instant = first || (changeStamped && change!.instant) || prev.width != width
        let startMs = (keyChanged || changeStamped) && change != nil ? change!.at : now
        let pressChanged = prev.pressed != scene.pressed
        let mode: MotionMode = instant ? .instant : reduced ? .reduced : .spring
        let idle = ShapeTarget(.idle, measure: .empty, screenWidth: width, metrics: metrics)

        let joining = scene.joining
        if joining != prev.joining {
            last.joining = joining
            if joining != nil || !keyChanged {
                anim.leadJoin(
                    joinAt: joining.map { $0 / 1000 }, at: now / 1000, idleRight: idle.right,
                    restLeft: prev.target?.bubbleLeft ?? anim.bubbleLeft.target, motion: motion, mode: mode)
            }
            if !keyChanged {
                let joinTransition = ShapeTransition(from: .minimal, to: .expanded, swap: true, swelling: true, alert: false)
                let join = motion.contentMotion(joinTransition).bubbleExit
                if let joining, let join, join.delay < 0, !reduced, !instant {
                    var out = AnimatedValue(1, precision: 0.001)
                    out.set(0, at: joining / 1000, bubbleCut(join))
                    bubbleExits[scene.key] = out
                } else {
                    bubbleExits[scene.key] = nil
                }
            }
        }
        last.handingOff = scene.handingOff
        last.alerting = scene.alerting
        if !keyChanged && !instant && !pressChanged && sameTarget(prev.target, target) { return false }

        let swap = prev.activityId != nil && scene.activityId != nil && !sameString(prev.activityId, scene.activityId)
        let transition = ShapeTransition(
            from: prev.kind, to: scene.kind, swap: swap, swelling: prev.pressed != nil, alert: prev.alerting)
        let t0 = startMs / 1000 + (mode == .spring && keyChanged && prev.alerting ? motion.lag[transition] : 0)
        rests[scene.key] = target
        let absorbing = anim.absorbsBubble(transition: transition, target: target, t0: t0)
        if keyChanged && mode == .spring && [.collapse, .alertCollapse, .collapseSplit].contains(transition) {
            keylineDip = t0
        }
        let sameShape = transition == .resize && mode == .spring && !pressChanged && sameTarget(prev.target, target)
        if (keyChanged && !sameShape) || !sameTarget(prev.target, target) || instant {
            shapeTransition = transition
            anim.retarget(ShapeChange(
                transition: transition, target: target, idle: idle, t0: t0, motion: motion, mode: mode))
        }
        if pressChanged && !(prev.pressed != nil && keyChanged) {
            anim.retargetPress(
                pressed: scene.pressed, style: scene.pressStyle, at: now / 1000, motion: motion, metrics: metrics, mode: mode,
                idle: scene.kind == .idle)
        }
        if keyChanged {
            let timing = contentTiming(
                motion.contentMotion(transition), absorbing: absorbing, alerting: prev.alerting,
                handingOff: prev.handingOff, width: target.right - target.left)
            enter(scene.key, timing: timing, changedAt: changedAt, t0: t0, mode: mode)
            leave(timing: timing, prev: prev, t0: t0, mode: mode)
            carryOver(shownBefore, changedAt: changedAt, mode: mode, timing: timing)
        }
        last = LastRetarget(
            key: scene.key, kind: scene.kind, changeId: change?.id, width: width, target: target,
            pressed: scene.pressed, joining: joining, activityId: scene.activityId, alerting: scene.alerting,
            handingOff: scene.handingOff)
        draw(now: now)
        return true
    }

    /// The current layer's measure, each width held against the last, its split fitted and kept.
    mutating func measured(_ scene: ContentScene, _ raw: ContentMeasures) -> ContentMeasure {
        let before = widths[scene.key]
        let split = raw.split.map { s in
            ContentMeasure.Split(
                attached: SlotPair(
                    leading: stableWidth(s.attached.leading, previous: before?.split?.attached.leading),
                    trailing: stableWidth(s.attached.trailing, previous: before?.split?.attached.trailing)),
                detached: SlotPair(
                    leading: stableWidth(s.detached.leading, previous: before?.split?.detached.leading),
                    trailing: stableWidth(s.detached.trailing, previous: before?.split?.detached.trailing)))
        }
        let measure = ContentMeasure(
            leading: stableWidth(raw.leading, previous: before?.leading),
            trailing: stableWidth(raw.trailing, previous: before?.trailing),
            attached: stableWidth(raw.attached, previous: before?.attached),
            detached: stableWidth(raw.detached, previous: before?.detached),
            split: split, expandedHeight: raw.expandedHeight)
        let splitShape = splitLayout(measure, metrics: metrics)
        if let splitShape, let split {
            let room = bubbleTrailing(
                split.detached, bubbleWidth: splitShape.bubbleRight - splitShape.bubbleLeft, metrics: metrics
            ).room
            fit(.splitDetachedTrailing, natural: split.detached.trailing, room: room)
        }
        widths[scene.key] = LayerSize(
            leading: measure.leading, trailing: measure.trailing, attached: measure.attached,
            detached: measure.detached, split: split, useSplit: splitShape != nil,
            regions: scene.kind == .expanded ? raw.regions : PerRegion())
        return measure
    }

    /// Brings the layer `key` in on `timing`, with the presences its slots come in on.
    mutating func enter(_ key: String, timing: ContentMotion, changedAt: Double, t0: Double, mode: MotionMode) {
        var current = presence[key] ?? AnimatedValue(0, precision: 0.001)
        let look = LayerLook(timing)
        looks[key] = look
        let lagSpan = look.lag
        let shownSince = (0...8).contains { current.value(at: changedAt / 1000 - lagSpan * Double($0) / 8) > 0.001 }
        if mode == .spring && shownSince { rejoins.insert(key) } else { rejoins.remove(key) }
        cutting.remove(key)
        removing.remove(key)
        bubbleExits[key] = nil
        bubbleEnters[key] = nil
        trailingEnters[key] = nil
        bubbleSettles[key] = nil
        partSteps[key] = nil
        leavingSlides[key] = nil
        if mode == .spring {
            if let own = timing.trailingEnter {
                var value = AnimatedValue(clamp01(current.value(at: t0)), precision: 0.001)
                value.set(1, at: t0, .spring(own.spring, delay: own.delay))
                trailingEnters[key] = value
            }
            if let own = timing.bubbleEnter {
                var value = AnimatedValue(clamp01(current.value(at: t0)), precision: 0.001)
                value.set(1, at: t0, .spring(own.spring, delay: own.delay))
                bubbleEnters[key] = value
            }
            if let settle = timing.bubbleSettle, settle.depth > 0 {
                var value = AnimatedValue(0, precision: 0.001)
                value.set(1, at: t0, .spring(settle.spring, delay: settle.delay))
                bubbleSettles[key] = value
            }
            if let step = timing.partStep {
                var value = AnimatedValue(0, precision: 0.001)
                value.set(1, at: t0, .tween(duration: 0, delay: step.at))
                value.set(0, at: t0, .spring(step.spring, delay: step.at))
                partSteps[key] = value
            }
        }
        current.set(1, at: t0, fadeOf(timing.enter, mode))
        presence[key] = current
    }

    /// Sends every leaving layer out on `timing`, keeping how far each had come.
    mutating func leave(timing: ContentMotion, prev: LastRetarget, t0: Double, mode: MotionMode) {
        let look = looks[scene!.key]!
        let leftWide = prev.kind == .compact && prev.target != nil
            && prev.target!.right - prev.target!.left >= (timing.exitWide?.from ?? .greatestFiniteMagnitude)
        let exitLook = leftWide ? look.leavingWide(timing.exitWide!) : look
        let carryResponseMin = motion.content.carryResponseMin
        for key in leavingKeys {
            let leavingPresence = presence[key]
            if let exit = timing.bubbleExit {
                let shown = clamp01(min(
                    leavingPresence?.value(at: t0) ?? 1, bubbleExits[key]?.value(at: t0) ?? 1))
                var out = AnimatedValue(shown, precision: 0.001)
                out.set(0, at: t0, mode == .spring ? bubbleCut(exit) : fadeOf(exit, mode))
                bubbleExits[key] = out
            }
            let was = looks[key]
            if mode != .spring {
                leavingSlides[key] = nil
            } else if let was, let leavingPresence, leavingPresence.target == 1 {
                leavingSlides[key] = nil
                let rejoined = rejoins.contains(key)
                let own = trailingEnters[key]
                func slideAt(_ time: Double) -> Double {
                    let trailing = enteringTrailing(
                        leavingPresence, own: own, delay: was.trailingDelay, time, rejoined: rejoined)
                    return was.trailingSlide * pow(1 - trailing, was.trailingSlidePower)
                }
                let offset = was.trailingSlide != 0 ? slideAt(t0) : 0
                if abs(offset) > 0.005 {
                    var slide = AnimatedValue(offset, precision: 0.005)
                    let spring = SpringConfig(
                        response: max(timing.exit.response, carryResponseMin), dampingFraction: carryDamping)
                    slide.set(
                        0, at: t0, .spring(spring),
                        from: MotionSample(value: offset, velocity: (offset - slideAt(t0 - speedStep)) / speedStep))
                    leavingSlides[key] = slide
                }
            }
            let comingIn = was != nil && leavingPresence?.target == 1
                && full(clamp01(leavingPresence!.value(at: t0))) < 1
            let goingOut = was != nil && leavingPresence?.target == 0
            let leavingClip = (comingIn || goingOut) && mode == .spring ? was!.clipFollow : 0
            let nearCut = mode == .spring && timing.exit.response < carryResponseMin
            let keepsExit = leavingPresence?.target == 0 && mode == .spring && (nearCut || cutting.contains(key))
            if !keepsExit {
                let exitFade = fadeOf(timing.exit, mode)
                presence[key]?.set(0, at: t0, exitFade)
                if nearCut { cutting.insert(key) } else { cutting.remove(key) }
            }
            if !(keepsExit && was != nil) {
                var leaving = exitLook
                leaving.bubbleDelay = 0
                leaving.trailingDelay = 0
                leaving.centerDelay = 0
                leaving.regions = PerRegion()
                leaving.clipFollow = leavingClip
                looks[key] = leaving
            }
        }
    }

    /// How a presence moves to its target on `spring`: snapped, eased, or on that spring.
    func fadeOf(_ spring: DelayedSpring, _ mode: MotionMode) -> Transition {
        switch mode {
        case .instant: .instant
        case .reduced: .tween(duration: motion.reduced.duration)
        case .spring: .spring(spring.spring, delay: spring.delay)
        }
    }
}
