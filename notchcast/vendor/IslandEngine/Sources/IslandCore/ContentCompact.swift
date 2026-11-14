import Foundation

extension LayerPainter {
    /// The compact pill's leading accent and trailing text.
    func compact(_ canvas: inout LayerCanvas) {
        let pad = m.compact.edgePadding
        let h = m.compact.height
        let lx = pad + size.leading / 2
        let tx = restBox.w - pad - size.trailing / 2
        let squeeze = squeezeOf(true)
        let leadFrom = entering ? look.scale : (look.exitTravel ?? look.scale)
        let lead = onGrid(
            slotAt(lx, restBox.h / 2, p, leading: true, w: size.leading, squeeze: squeeze, from: leadFrom),
            restAt(lx, restBox.h / 2), size.leading, h)
        let trailFrom = entering && look.trailingScale != nil ? look.trailingScale! : look.scale
        let trailAt = onGrid(
            slotAt(tx, restBox.h / 2, pTrailing, leading: false, from: trailFrom), restAt(tx, restBox.h / 2),
            size.trailing, h)
        let trailX = trailAt.x + slide(-1, pTrailing)
        let glow = entering ? look.enterGlow : 0
        put(
            .leading, lead.x, lead.y, size.leading, h, p, k, &canvas, power: leadFade, scaleAt: { accentScale($0) },
            blurAt: { accentBlur($0) }, stretch: squeeze, glow: glow, blurStretch: squeeze.squareRoot())
        put(
            .trailing, trailX, trailAt.y, size.trailing, h, pTrailing, k, &canvas, power: fade,
            scaleAt: { trailFrom + (1 - trailFrom) * $0 }, blurAt: { trailingBlur($0) }, glow: glow)
    }
}
