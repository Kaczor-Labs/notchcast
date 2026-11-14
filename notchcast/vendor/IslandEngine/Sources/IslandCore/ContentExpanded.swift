import Foundation

extension LayerPainter {
    /// The expanded view: its place on the grid, its shared blur and clip, and each region in it.
    func expanded(_ canvas: inout LayerCanvas) {
        let ex = settle(rest != nil ? box.x + toGrid(restBox.x) : box.x)
        let ey = settle(rest != nil ? box.y + toGrid(restBox.y) : box.y)
        if canvas.has(.expanded) && canvas.drawn == nil {
            canvas.styles[.expanded]!.transform = SlotTransform(x: ex, y: ey)
            canvas.styles[.expanded]!.willChange = p >= 1 && k == 1 ? .auto : .moving
        }
        let sharedPeak = regionSlots.reduce(peakBlur) { low, pair in
            canvas.has(pair.0) && size.regions[pair.1] != nil ? min(low, peakOf(pair.1)) : low
        }
        let unused = SlotDraw(opacity: 1, sx: 1, sy: 1)
        var sharedBase = unused
        sharedBase.blur = reduced ? 0 : pow(remaining(p, look.enterClear), sharpen) * sharedPeak
        let shared = sharedBase.blur
        let rootDrawn = blend(.root, sharedBase, &canvas)?.0
        if let rootDrawn {
            canvas.styles[.root]!.clip = SlotClip.none
            canvas.styles[.root]!.blur = rootDrawn.blur > 0.01 ? rootDrawn.blur : 0
        }
        expandedClip(&canvas)
        var skirted = false
        for (slot, region) in regionSlots {
            guard canvas.has(slot), let centre = size.regions[region] else { continue }
            skirted = self.region(slot, region, centre, shared: shared, unused: unused, &canvas) || skirted
        }
        // One copy of the clipped view draws every region's wide part, `width` wide with the root's blur.
        if let skirt, skirted, canvas.has(.expandedClip), canvas.has(.expanded) {
            let rootBlur = rootDrawn?.blur ?? 0
            let blur = max(0, skirt.width * skirt.width - rootBlur * rootBlur).squareRoot()
            canvas.styles[.expandedClip]!.echo = SlotEcho(opacity: 1, blur: blur)
        }
    }

    func peakOf(_ region: ExpandedRegion) -> Double { entering ? (look.regions[region]?.peak ?? peakBlur) : peakBlur }

    func expandedClip(_ canvas: inout LayerCanvas) {
        let pill = frame.pill
        let hasPill = !frame.paths.pill.isEmpty
        let follows = !reduced && rest != nil && hasPill ? look.clipFollow : 0
        let restRadius = rest?.radius ?? pill.radius
        let resting = abs(sx - 1) < 1e-9 && abs(sy - 1) < 1e-9 && abs(pill.radius - restRadius) < 1e-9
        let followBase = SlotDraw(opacity: 1, sx: 1, sy: 1, follow: resting ? 0 : follows)
        guard canvas.has(.expandedClip), let (followDrawn, carried) = blend(.expandedClip, followBase, &canvas)
        else { return }
        let clipFollow = !carried ? follows : rest != nil && hasPill ? clamp01(followDrawn.follow) : 0
        if clipFollow > 0 {
            var path = followingClip(
                x: box.x, y: box.y, width: box.w, height: box.h, radius: pill.radius, restWidth: restBox.w,
                restHeight: restBox.h, restRadius: restRadius, cap: m.contentClip.radius, follow: clipFollow)
            path.elements += frame.paths.bubbleClip.elements
            canvas.styles[.expandedClip]!.clip = .path(path)
        } else {
            canvas.styles[.expandedClip]!.clip = hasPill ? .path(frame.paths.clip) : SlotClip.none
        }
    }

    /// Draws one region; true when it draws a wide part this frame.
    @discardableResult
    func region(
        _ slot: SlotName, _ region: ExpandedRegion, _ centre: Vec, shared: Double, unused: SlotDraw,
        _ canvas: inout LayerCanvas
    ) -> Bool {
        let anchor = look.regionBottomAnchor[region] ?? look.bottomAnchor
        let dropY = reduced ? 0 : anchor * (box.h - restBox.h - centre.y * (sy - 1))
        let centerLag = region == .center && look.centerDelay > 0
            ? RegionLag(fade: look.centerDelay, blur: look.centerDelay) : nil
        let lag = entering && !reduced ? (look.regions[region] ?? centerLag) : nil
        func behind(_ delay: Double) -> Double {
            delay != 0 ? full(clamp01(lagged(value, t, delay: delay, rejoined: rejoined) ?? 1)) : p
        }
        let pr = lag.map { behind($0.fade) } ?? p
        let pb = lag.map { behind($0.blur) } ?? p
        let from = lag?.scale ?? look.scale
        let scale = k * (reduced ? 1 : from + (1 - from) * pb)
        let lift = reduced ? 0 : (lag?.lift ?? 0) * (1 - pb)
        let soften = max(0, 1 + (lag?.soften ?? 0) * (1 - pb))
        let own = pow(remaining(pb, look.enterClear), sharpen) * peakOf(region) * soften
        let blur = reduced ? 0 : max(0, own * own - shared * shared).squareRoot() / max(scale, 0.05)
        let lagOpacity = pow(pr, entering ? (lag?.power ?? fade) : (look.regionExitFade[region] ?? fade))
        let lead = lag?.lead ?? 0
        var base = unused
        base.opacity = reduced ? reducedOpacity(pr) : lead > 0 ? max(lagOpacity, min(lead, pow(p, fade))) : lagOpacity
        base.blur = blur
        base.x = settle(centre.x * (sx - 1))
        base.y = settle(centre.y * (sy - 1) + dropY)
        base.sx = scale
        base.sy = scale
        base.lift = lift
        base.skirt = skirt != nil && !reduced ? skirtWeight(skirt, sigma: own, leaving: !entering) * look.skirt : 0
        guard let (d, _) = blend(slot, base, &canvas) else { return false }
        var style = canvas.styles[slot]!
        style.opacity = d.skirt > 0 ? d.opacity * (1 - d.skirt * dim) : d.opacity
        style.blur = d.blur > 0.01 ? d.blur : 0
        style.transform = SlotTransform(x: d.x, y: d.y, lift: d.lift > 0.005 ? d.lift : nil, sx: d.sy, sy: d.sy)
        if d.skirt > 0 { style.echo = SlotEcho(opacity: d.opacity * d.skirt, blur: 0) }
        canvas.styles[slot] = style
        return d.skirt > 0
    }
}
