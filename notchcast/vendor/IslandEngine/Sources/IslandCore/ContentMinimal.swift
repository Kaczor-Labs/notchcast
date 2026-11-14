import Foundation

extension LayerPainter {
    /// The minimal island's attached slots and the bubble row's, split or not.
    func minimal(_ canvas: inout LayerCanvas) {
        let slotH = m.minimal.height
        let split = size.useSplit ? size.split : nil
        if canvas.drawn == nil {
            for (name, visible) in [
                (SlotName.attached, split == nil), (.detached, split == nil), (.splitAttachedLeading, split != nil),
                (.splitAttachedTrailing, split != nil), (.splitDetachedLeading, split != nil),
                (.splitDetachedTrailing, split != nil),
            ] where canvas.has(name) {
                canvas.styles[name]!.visibility = visible ? .inherit : .hidden
            }
        }
        let row = BubbleRow(self)
        if row.band == nil && canvas.drawn == nil {
            for name in [SlotName.detached, .splitDetachedLeading, .splitDetachedTrailing] where canvas.has(name) {
                canvas.styles[name]!.clip = SlotClip.none
            }
        }
        if canvas.drawn != nil && row.band != nil { canvas.drawn!.capTravel = row.capTravel }
        if let split {
            minimalSplit(split, row, slotH, &canvas)
        } else {
            let ax = m.minimal.attached.outerPadding + size.attached / 2
            let lead = onGrid(
                row.onRow(slotAt(ax, restBox.h / 2, p, leading: true, w: size.attached)), restAt(ax, restBox.h / 2),
                size.attached, slotH)
            put(
                .attached, lead.x, lead.y, size.attached, slotH, p, k, &canvas, power: fade,
                scaleAt: { accentScale($0) }, blurAt: { accentBlur($0) })
            let d0 = onGrid(
                Vec(x: row.slot(row.bw / row.gb / 2, row.restW / 2), y: row.y),
                Vec(x: row.restX + row.restW / 2, y: row.bandMid), size.detached, slotH)
            let dCx = d0.x + row.exitSlide
            put(
                .detached, dCx, d0.y, size.detached, slotH, pBubble, row.gb, &canvas, power: row.fade,
                scaleAt: { row.accentScaleAt($0) }, blurAt: { bubbleAccentBlur($0) }, stretch: row.accentStretch,
                band: row.capped(rest: row.restX + row.restW / 2, now: dCx, w: size.detached))
        }
    }

    func minimalSplit(_ split: ContentMeasure.Split, _ row: BubbleRow, _ slotH: Double, _ canvas: inout LayerCanvas) {
        let s = m.split
        let lw = split.attached.leading
        let lx = s.attached.outerPadding + lw / 2
        let tx = s.attached.outerPadding + lw + (lw > 0 ? s.attached.gap : 0) + split.attached.trailing / 2
        let stepValue = entering && !reduced && look.partStep != nil ? partStep : nil
        let stepNow = stepValue.map { look.partStep!.by * $0.value(at: t) } ?? 0
        let step = abs(stepNow) < 0.005 ? 0 : stepNow
        let lead = onGrid(
            row.onRow(slotAt(lx, restBox.h / 2, p, leading: true, w: lw)).moved(step), restAt(lx, restBox.h / 2), lw,
            slotH)
        let trailAt = onGrid(
            row.onRow(slotAt(tx, restBox.h / 2, pTrailing, leading: false)).moved(step), restAt(tx, restBox.h / 2),
            split.attached.trailing, slotH)
        put(
            .splitAttachedLeading, lead.x, lead.y, lw, slotH, p, k, &canvas, power: leadFade,
            scaleAt: { accentScale($0) }, blurAt: { accentBlur($0) })
        put(
            .splitAttachedTrailing, trailAt.x + slide(1, pTrailing), trailAt.y, split.attached.trailing, slotH,
            pTrailing, k, &canvas, power: fade, blurAt: { trailingBlur($0) })
        let dl = split.detached.leading
        let dlx = s.detached.outerPadding + dl / 2
        let dl0 = onGrid(Vec(x: row.slot(dlx, dlx), y: row.y), Vec(x: row.restX + dlx, y: row.bandMid), dl, slotH)
        let dlCx = dl0.x + row.exitSlide
        put(
            .splitDetachedLeading, dlCx, dl0.y, dl, slotH, pBubble, row.gb, &canvas, power: row.fade,
            scaleAt: { row.accentScaleAt($0) }, blurAt: { bubbleAccentBlur($0) }, stretch: row.accentStretch,
            band: row.capped(rest: row.restX + dlx, now: dlCx, w: dl))
        let trailing = bubbleTrailing(split.detached, bubbleWidth: row.restW, metrics: m)
        let dtx = trailing.fromRight
        let textSlide = entering && !reduced && rest != nil
            ? look.bubbleTrailingSlide.map { $0.by * pow(1 - pBubbleText, $0.power) } ?? 0 : 0
        let textBlur = entering ? look.bubbleTrailingBlur : nil
        let peak = look.bubbleBlurMax ?? peakBlur
        let dt0 = onGrid(
            Vec(x: row.slot(row.bw / row.gb - dtx, row.restW - dtx) + textSlide, y: row.y),
            Vec(x: row.restX + row.restW - dtx, y: row.bandMid), trailing.width, slotH)
        put(
            .splitDetachedTrailing, dt0.x, dt0.y, trailing.width, slotH, pBubbleText, row.gb, &canvas,
            power: entering && look.bubbleTrailingFade > 0 ? look.bubbleTrailingFade : row.fade,
            scaleAt: { row.scaleAt($0) },
            blurAt: { pres in textBlur.map { min(peak, $0.by * pow(1 - pres, $0.power)) } ?? bubbleBlur(pres) },
            stretch: row.stretch, band: row.band)
    }
}

/// The bubble row's frame-wide numbers a minimal layer's bubble slots are placed from.
struct BubbleRow {
    let y: Double
    let bw: Double
    let gb: Double
    let restX: Double
    let restW: Double
    let bandMid: Double
    let band: Band?
    let lobe: Double?
    let from: Double
    let under: Double
    let fade: Double
    let stretch: Double
    let accentStretch: Double
    let lead: Double
    let exitSlide: Double
    let spread: Double
    let sharpen: Double
    let pBubble: Double
    let bubbleX: Double
    let pillEnd: Double
    let capTravel: Double?
    let toRow: Double

    init(_ l: LayerPainter) {
        let look = l.look
        let bubble = l.frame.bubble
        let rest = l.rest
        let bubbleMid = bubble.y + bubble.height / 2
        let boxMid = l.box.y + l.box.h / 2
        let row = bubble.height > 0 ? bubble.height : (rest?.bubbleHeight ?? 0)
        let room = max(0, l.box.h - row) / 2
        let by = l.reduced
            ? (bubble.height > 0 ? bubbleMid : boxMid)
            : row > 0 ? bubbleMid + max(-room, min(room, boxMid - bubbleMid)) : boxMid
        bw = bubble.span
        from = l.entering ? look.bubbleScale : look.scale
        spread = l.entering && !l.reduced && rest != nil ? look.bubbleSpread : 0
        restX = rest.map { l.width / 2 + $0.bubbleLeft } ?? bubble.x
        restW = rest.map { $0.bubbleRight - $0.bubbleLeft } ?? bw
        gb = bubble.height > 0 ? bubble.scale : 1
        bandMid = rest.map { $0.top + $0.height / 2 } ?? 0
        band = rest != nil && !l.reduced
            ? Band(top: bandMid - (rest!.height / 2) * gb, bottom: bandMid + (rest!.height / 2) * gb, cap: nil) : nil
        let origin = l.entering && look.bubbleOrigin != nil
            ? band.map { $0.top + look.bubbleOrigin! * ($0.bottom - $0.top) } : nil
        pBubble = l.pBubble
        lobe = origin.map { _ in
            clamp01(pow((1 - l.pBubble) / max(1 - look.bubbleHold, 0.01), look.bubbleResolve ?? look.bubbleSharpen))
        }
        let closing = lobe ?? pow(1 - l.pBubble, look.sharpen)
        let settling = l.entering && !l.reduced ? l.bubbleSettle : nil
        let shortfall = settling.map { look.bubbleSettle * (1 - clamp01($0.value(at: l.t))) } ?? 0
        under = shortfall < settledShare ? 0 : shortfall
        fade = l.entering ? (look.bubbleFade ?? l.fade) : l.fade
        let stretching = l.entering && !l.reduced && rest != nil
        stretch = stretching ? 1 + look.bubbleStretch * closing : 1
        accentStretch = stretching ? 1 + look.bubbleStretch * pow(closing, look.bubbleStretchPower) : 1
        let emerged = bubble.x + row - (l.restBox.x + l.restBox.w)
        let leadShare = look.bubbleLeadRamp > 0 ? pow(clamp01(emerged / look.bubbleLeadRamp), look.bubbleLeadPower) : 1
        lead = !l.reduced && look.bubbleLead != 0 ? look.bubbleLead * l.bubbleLeftVelocity * leadShare : 0
        exitSlide = !l.entering && !l.reduced && look.bubbleExitSlide != 0
            ? -look.bubbleExitSlide * pow(1 - l.p, look.bubbleExitSlidePower) : 0
        sharpen = look.sharpen
        bubbleX = bubble.x
        pillEnd = l.restBox.x + l.restBox.w
        let holding = l.capHold != nil && (!l.entering || l.pBubble < 0.995)
        capTravel = holding
            ? l.capHold!
            : !l.entering || look.bubbleCap <= 0 || l.pBubble >= 0.995 ? nil : 1 - pow(1 - l.pBubble, look.bubbleCap)
        toRow = l.entering && band != nil && !l.reduced ? look.rowAnchor : 0
        let rise = Self.scale(lobe, from, l.pBubble)
        y = origin.map { [bandMid] in $0 + (bandMid - $0) * rise } ?? by
    }

    static func scale(_ lobe: Double?, _ from: Double, _ pres: Double) -> Double {
        lobe.map { 1 + (from - 1) * $0 } ?? from + (1 - from) * pres
    }

    func scaleAt(_ pres: Double) -> Double { Self.scale(lobe, from, pres) }

    func accentScaleAt(_ pres: Double) -> Double { scaleAt(pres) * (1 - under) }

    /// Centre x of a bubble slot `dx` from the bubble's left edge, `dxRest` at rest.
    func slot(_ dx: Double, _ dxRest: Double) -> Double {
        if spread <= 0 { return bubbleX + lead + dx * gb }
        let centre = restX + restW / 2
        return centre + (restX + dxRest - centre) * (1 + spread * pow(1 - pBubble, sharpen))
    }

    /// The band capped for a slot resting at `rest`, now centred at `now`, `w` wide.
    func capped(rest: Double, now: Double, w: Double) -> Band? {
        guard let band, let travel = capTravel else { return band }
        let r = (band.bottom - band.top) / 2
        let end = max(pillEnd + (rest + r - pillEnd) * travel, now + (w / 2) * gb)
        return Band(top: band.top, bottom: band.bottom, cap: end - r)
    }

    func onRow(_ s: Vec) -> Vec { toRow > 0 ? Vec(x: s.x, y: s.y + (bandMid - s.y) * toRow) : s }
}

extension Vec {
    fileprivate func moved(_ dx: Double) -> Vec { dx == 0 ? self : Vec(x: x + dx, y: y) }
}
