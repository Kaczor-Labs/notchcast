import Foundation

/// A slot's or layer's place and size on screen.
struct LayerBox: Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// A bubble slot's band on screen, its right end capped at `cap` when set.
struct Band: Sendable {
    var top: Double
    var bottom: Double
    var cap: Double?
}

/// What one layer's slots draw on a frame: their styles, or their numbers for a carry.
struct LayerCanvas: Sendable {
    var styles: [SlotName: SlotStyle]
    /// Each slot's numbers, kept instead of written while sampling.
    var drawn: LayerDraw?
    /// The brightest opacity the layer's slots draw, carries included.
    var drawnMax = 0.0

    /// Whether the layer mounts `name`.
    func has(_ name: SlotName) -> Bool { styles[name] != nil }
}

/// Everything one layer's slots are drawn from on one frame.
struct LayerPainter: Sendable {
    let m: IslandMetrics
    let look: LayerLook
    let reduced: Bool
    let still: Bool
    let dpr: Double
    let t: Double
    let width: Double
    let frame: FrameGeometry
    let box: LayerBox
    let restBox: LayerBox
    let rest: ShapeTarget?
    let size: LayerSize
    let skirt: BlurSkirt?
    let dim: Double
    let value: AnimatedValue?
    let p: Double
    let entering: Bool
    let rejoined: Bool
    let fade: Double
    let pBubbleLayer: Double
    let pBubbleText: Double
    let pBubble: Double
    let pTrailing: Double
    let carry: Carry?
    let carryWeight: Double
    let carrySpeed: Double
    let sx: Double
    let sy: Double
    let k: Double
    let kept: Double
    let bubbleSettle: AnimatedValue?
    let partStep: AnimatedValue?
    let capHold: Double??
    let bubbleLeftVelocity: Double
    let presenceGone: Bool

    var leadFade: Double { entering ? fade * look.leadingFade : fade * look.exitLeadingFade }
    var peakBlur: Double { entering ? look.enterBlur : look.blur }
    var sharpen: Double { entering ? look.sharpen : 1 }

    func toGrid(_ v: Double) -> Double { jsRound(v * dpr) / dpr - v }

    func settle(_ v: Double) -> Double {
        if !still { return v }
        let on = jsRound(v * dpr)
        return abs(v * dpr - on) < gridSnap ? on / dpr : v
    }

    func remaining(_ pres: Double, _ clear: Double) -> Double { blurLeft(pres, clear: entering ? clear : 0) }

    func layerBlur(_ pres: Double) -> Double { pow(remaining(pres, look.enterClear), sharpen) * peakBlur }

    func accentBlur(_ pres: Double) -> Double {
        entering ? layerBlur(pres) : pow(1 - pres, look.exitSharpen) * (look.exitBlur ?? look.blur)
    }

    var accentFrom: Double { entering ? (look.enterScale ?? look.scale) : (look.exitScale ?? look.scale) }

    func accentScale(_ pres: Double) -> Double { accentFrom + (1 - accentFrom) * pres }

    func bubbleBlur(_ pres: Double) -> Double {
        entering
            ? min(look.bubbleBlurMax ?? peakBlur, pow(1 - pres, look.bubbleSharpen) * look.bubbleBlur) : layerBlur(pres)
    }

    func bubbleAccentBlur(_ pres: Double) -> Double {
        if !entering, let exit = look.bubbleExitBlur { return (1 - pres) * exit }
        return bubbleBlur(pres)
    }

    func trailingBlur(_ pres: Double) -> Double {
        let peak = entering && look.trailingEnterBlur != nil ? look.trailingEnterBlur! : peakBlur
        return pow(remaining(pres, look.trailingEnterClear), sharpen) * peak
    }

    /// Adds the carry to a slot's numbers, or keeps them while sampling; `carried` is false for `base`.
    func blend(_ name: SlotName, _ base: SlotDraw, _ canvas: inout LayerCanvas) -> (SlotDraw, carried: Bool)? {
        let carried = carryWeight > 0 ? carry?.slots[name] : nil
        let out = carried.map { addCarry(base, $0, weight: carryWeight, lag: carrySpeed) } ?? base
        if name != .root && name != .expandedClip { canvas.drawnMax = max(canvas.drawnMax, out.opacity) }
        if canvas.drawn != nil {
            canvas.drawn!.slots[name] = out
            return nil
        }
        return (out, carried != nil)
    }

    /// Writes a slot's presence and place: centred at `cx`, `cy`, its own size `w` by `h`.
    func put(
        _ name: SlotName, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ pres: Double, _ follow: Double,
        _ canvas: inout LayerCanvas, power: Double? = nil, scaleAt: ((Double) -> Double)? = nil,
        blurAt: ((Double) -> Double)? = nil, stretch: Double = 1, band: Band? = nil, glow: Double = 0,
        blurStretch: Double = 1
    ) {
        guard canvas.has(name) else { return }
        let power = power ?? fade
        let blurAt = blurAt ?? { layerBlur($0) }
        let presenceScale = reduced ? 1 : (scaleAt?(pres) ?? look.scale + (1 - look.scale) * pres)
        let s = follow * presenceScale
        let blur = reduced ? 0 : blurAt(pres) / max(s * blurStretch, 0.05)
        let copies = skirt != nil
        let base = SlotDraw(
            opacity: reduced ? reducedOpacity(pres) : max(pow(pres, power), glow * p),
            blur: blur,
            x: settle(cx - w / 2),
            y: settle(cy - h / 2),
            sx: s * stretch,
            sy: s,
            bandTop: band?.top ?? 0,
            bandBottom: band?.bottom ?? 0,
            cap: band?.cap ?? 0,
            skirt: copies ? skirtWeight(skirt, sigma: reduced ? 0 : blurAt(pres), leaving: !entering) * look.skirt : 0)
        guard let (d, carried) = blend(name, base, &canvas) else { return }
        let wide = copies ? d.skirt : 0
        var style = canvas.styles[name]!
        style.opacity = wide > 0 ? d.opacity * (1 - wide * dim) : d.opacity
        style.blur = d.blur > 0.01 ? d.blur : 0
        style.transform = SlotTransform(x: d.x, y: d.y, sx: d.sx, sy: d.sy)
        if let skirt, wide > 0 { style.echo = SlotEcho(opacity: d.opacity * wide, blur: skirtBlur(skirt, scale: d.sy)) }
        let resting = !carried && pres >= 1 && s == 1 && stretch == 1 && blur <= 0.01
        style.willChange = resting ? .auto : .moving
        if let band {
            let midX = carried ? cx + (d.x - base.x) : cx
            let midY = carried ? cy + (d.y - base.y) : cy
            let syc = max(d.sy, 0.05)
            let top = h / 2 + (d.bandTop - midY) / syc
            let bottom = h / 2 + (d.bandBottom - midY) / syc
            let reach = bandReach / syc
            if band.cap == nil {
                style.clip = .band(reach: reach, top: top, right: w + reach, bottom: bottom)
            } else {
                let sxc = max(d.sx, 0.05)
                style.clip = .cappedBand(
                    reach: reach, top: top, capX: w / 2 + (d.cap - midX) / sxc,
                    rx: (d.bandBottom - d.bandTop) / 2 / sxc, ry: (bottom - top) / 2, bottom: bottom)
            }
        }
        canvas.styles[name] = style
    }

    func at(_ fx: Double, _ fy: Double) -> Vec { Vec(x: box.x + fx * sx, y: box.y + fy * sy) }

    func squeezeOf(_ leading: Bool) -> Double {
        if !entering || !leading || reduced { return 1 }
        let byWidth = look.enterSqueeze > 0 && sx < 1 ? pow(sx, look.enterSqueeze) : 1
        let byPresence = look.enterNarrow > 0 ? max(0.1, pow(p, look.enterNarrow)) : 1
        return byWidth * byPresence
    }

    func inward(_ w: Double, _ pres: Double, _ squeeze: Double) -> Double {
        squeeze < 1 ? (w / 2) * k * accentScale(pres) * (1 - squeeze) * (1 - 2 * look.enterSqueezeOrigin) : 0
    }

    func slide(_ toward: Double, _ pres: Double) -> Double {
        if reduced { return 0 }
        if entering {
            return look.trailingSlide != 0 ? toward * look.trailingSlide * pow(1 - pres, look.trailingSlidePower) : 0
        }
        return kept != 0 ? toward * kept : 0
    }

    /// `now` moved by what puts the resting centre `restCentre` of a `w` by `h` slot on the grid.
    func onGrid(_ now: Vec, _ restCentre: Vec, _ w: Double, _ h: Double) -> Vec {
        guard rest != nil else { return now }
        return Vec(x: now.x + toGrid(restCentre.x - w / 2), y: now.y + toGrid(restCentre.y - h / 2))
    }

    func restAt(_ fx: Double, _ fy: Double) -> Vec { Vec(x: restBox.x + fx, y: restBox.y + fy) }

    /// A compact or split slot's centre, `fx` from the resting left edge, at presence `pres`.
    func slotAt(
        _ fx: Double, _ fy: Double, _ pres: Double, leading: Bool, w: Double = 0, squeeze: Double = 1,
        from: Double? = nil
    ) -> Vec {
        let from = from ?? look.scale
        let share = at(fx, fy)
        var ride = 0.0
        if let r = look.trailingRide {
            let rideBy = leading || reduced ? 0 : r.by * (box.x + box.w - (restBox.w - fx) - share.x)
            ride = max(-r.max, min(r.max, rideBy))
        }
        let proportional = Vec(x: share.x + ride, y: share.y)
        let anchor = leading
            ? look.anchor : (!entering && look.trailingExitAnchor != nil ? look.trailingExitAnchor! : max(0, look.anchor))
        if anchor == 0 || reduced { return Vec(x: proportional.x + inward(w, pres, squeeze), y: proportional.y) }
        let s = k * (from + (1 - from) * pres)
        let centred = box.x + box.w / 2 + (fx - restBox.w / 2) * s
        let x = proportional.x + (centred - proportional.x) * anchor
        if !leading || !entering || anchor >= 0 || w <= 0 {
            return Vec(x: x + inward(w, pres, squeeze), y: proportional.y)
        }
        let drawn = k * accentScale(pres)
        return Vec(x: min(x, restBox.x + fx + (w / 2) * (1 - drawn)) + inward(w, pres, squeeze), y: proportional.y)
    }
}

extension ContentStage {
    /// Draws a frame at `now` (ms); `still` is the closing draw at rest, which puts slots on the grid.
    public mutating func draw(now: Double, still: Bool = false) {
        let width = islandScreenWidth(containerWidth: stageWidth, metrics: metrics)
        let t = now / 1000
        let frame = anim.frame(at: t, stageWidth: width, metrics: metrics)
        frameClip = frame.paths.pill.isEmpty ? nil : frame.paths.clip
        drawShape(frame, t)
        if reduced { carries = [:] }
        write(paint(frame, t, width: width, still: still, sampling: nil).styles)
    }

    /// Each layer's numbers at `now` (ms), with or without the carries in force.
    func sample(_ now: Double, carried: Bool) -> StringMap<LayerDraw> {
        let width = islandScreenWidth(containerWidth: stageWidth, metrics: metrics)
        let t = now / 1000
        let frame = anim.frame(at: t, stageWidth: width, metrics: metrics)
        return paint(frame, t, width: width, still: false, sampling: carried).drawn
    }

    mutating func drawShape(_ frame: FrameGeometry, _ t: Double) {
        let shadow = metrics.expanded.shadow
        let alpha = reduced ? (frame.expansion >= 1 ? shadow.opacity : 0) : shadow.opacity * frame.shadow
        let on = alpha > 0.002
        let keyline = keylineAt(
            frame, t, keyline: scene?.keyline ?? 0, idle: scene?.kind == .idle, leaving: !leavingKeys.isEmpty,
            dipAt: keylineDip, reduced: reduced, metrics: metrics, motion: motion)
        self.shadow = ContentShadow(
            slope: on ? alpha : 0, tailSlope: on ? alpha * shadow.tail.strength : 0, filtered: on,
            keyline: keyline > 0.001 ? keyline : 0)
    }

    /// Every mounted layer's slots on `frame`; `sampling` keeps numbers instead, with carries or not.
    func paint(_ frame: FrameGeometry, _ t: Double, width: Double, still: Bool, sampling: Bool?)
        -> (styles: StringMap<[SlotName: SlotStyle]>, drawn: StringMap<LayerDraw>)
    {
        var styles: StringMap<[SlotName: SlotStyle]> = [:]
        var drawn: StringMap<LayerDraw> = [:]
        let skirt = reduced ? nil : motion.blurSkirt
        let box = LayerBox(x: frame.pill.x, y: frame.pill.y, w: frame.pill.width, h: frame.pill.height)
        let bubbleLeftVelocity = anim.bubblePose(at: t).left.velocity
        for layer in layers where layer.slots[.root] != nil {
            let key = layer.key
            let value = presence[key]
            if sampling != nil && value == nil { continue }
            let look = looks[key] ?? LayerLook.standard(metrics: metrics)
            let p = full(clamp01(value?.value(at: t) ?? 1))
            let entering = (value?.target ?? 1) == 1
            let rejoined = rejoins.contains(key)
            let fade = entering ? look.fade : look.exitFade
            let pBubbleLayer = entering && look.bubbleDelay != 0
                ? full(clamp01(lagged(value, t, delay: look.bubbleDelay, rejoined: rejoined) ?? 1)) : p
            let bubbleOut = bubbleExits[key]
            let cut = { (pres: Double) in bubbleOut.map { min(pres, clamp01($0.value(at: t))) } ?? pres }
            let ownBubble = entering ? bubbleEnters[key] : nil
            let pBubbleText = look.bubbleExitAccent ? pBubbleLayer : cut(pBubbleLayer)
            let pBubble = ownBubble.map { cut(full(clamp01($0.value(at: t)))) } ?? cut(pBubbleLayer)
            let pTrailing = entering
                ? enteringTrailing(
                    value, own: entering ? trailingEnters[key] : nil, delay: look.trailingDelay, t, rejoined: rejoined)
                : pow(p, look.trailingExitPower)
            let carry = sampling == false || reduced ? nil : carries[key]
            let carryWeight = carry.map { clamp01($0.weight.value(at: t)) } ?? 0
            let carrySpeed = carry.map { carryLag($0, t) } ?? 0
            var carriedOpacity = 0.0
            if let carry, carryWeight > 0 {
                for slot in carry.slots.values {
                    let speed = slot.speed != nil && slot.ratio == nil ? slot.speed!.opacity * carrySpeed : 0
                    carriedOpacity = max(carriedOpacity, abs(slot.delta.opacity * carryWeight + speed))
                }
            }
            let presenceGone = p <= 0.001 && max(pBubble, pBubbleText) <= 0.001 && carriedOpacity <= 0.001
            var canvas = LayerCanvas(styles: layer.slots, drawn: sampling != nil ? LayerDraw(shown: true, slots: [:]) : nil)
            if sampling == nil {
                for name in canvas.styles.keys { canvas.styles[name]!.echo = nil }
            }
            if sampling == nil && layer.kind != .expanded {
                canvas.styles[.root]?.clip = frameClip.map { .path($0) } ?? SlotClip.none
                canvas.styles[.root]?.blur = 0
            }
            let size = widths[key] ?? .empty
            let rest = rests[key]
            let restBox = rest.map { LayerBox(x: width / 2 + $0.left, y: $0.top, w: $0.right - $0.left, h: $0.height) }
                ?? box
            let sx = restBox.w > 0.5 ? box.w / restBox.w : 1
            let sy = restBox.h > 0.5 ? box.h / restBox.h : 1
            let c = metrics.content
            let k = reduced ? 1 : full(min(c.followMax, max(c.followMin, pow(sx * sy, (look.follow ?? c.follow) / 2))))
            let painter = LayerPainter(
                m: metrics, look: look, reduced: reduced, still: still, dpr: dpr, t: t, width: width, frame: frame,
                box: box, restBox: restBox, rest: rest, size: size, skirt: skirt, dim: skirtDim(skirt), value: value,
                p: p, entering: entering, rejoined: rejoined, fade: fade, pBubbleLayer: pBubbleLayer,
                pBubbleText: pBubbleText, pBubble: pBubble, pTrailing: pTrailing, carry: carry,
                carryWeight: carryWeight, carrySpeed: carrySpeed, sx: sx, sy: sy, k: k,
                kept: entering ? 0 : (leavingSlides[key]?.value(at: t) ?? 0), bubbleSettle: bubbleSettles[key],
                partStep: partSteps[key], capHold: capHolds[key], bubbleLeftVelocity: bubbleLeftVelocity,
                presenceGone: presenceGone)
            switch layer.kind {
            case .idle: break
            case .compact: painter.compact(&canvas)
            case .minimal: painter.minimal(&canvas)
            case .expanded: painter.expanded(&canvas)
            }
            let hidden = presenceGone && (!entering || canvas.drawnMax <= 0.001)
            if var layerDraw = canvas.drawn {
                layerDraw.shown = !hidden
                drawn[key] = layerDraw
            } else {
                canvas.styles[.root]?.visibility = hidden ? .hidden : .visible
                styles[key] = canvas.styles
            }
        }
        return (styles, drawn)
    }
}
