import CoreGraphics
import Foundation
import IslandCore

extension IslandPath {
    /// The outline as a `CGPath` in the same numbers: screen coordinates, origin top left, y down.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        for element in elements {
            switch element {
            case .move(let p):
                current = CGPoint(x: p.x, y: p.y)
                path.move(to: current)
            case .line(let p):
                current = CGPoint(x: p.x, y: p.y)
                path.addLine(to: current)
            case .quad(let control, let to):
                current = CGPoint(x: to.x, y: to.y)
                path.addQuadCurve(to: current, control: CGPoint(x: control.x, y: control.y))
            case .cubic(let control1, let control2, let to):
                current = CGPoint(x: to.x, y: to.y)
                path.addCurve(
                    to: current, control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y))
            case .arc(let rx, let ry, let to):
                let end = CGPoint(x: to.x, y: to.y)
                path.addSVGArc(from: current, rx: rx, ry: ry, to: end)
                current = end
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

extension CGMutablePath {
    /// An SVG `A rx ry 0 0 1 x y`: unrotated, the small arc, clockwise as drawn with y down.
    fileprivate func addSVGArc(from start: CGPoint, rx: Double, ry: Double, to end: CGPoint) {
        guard rx > 0, ry > 0, start != end else {
            addLine(to: end)
            return
        }
        let hx = (start.x - end.x) / 2
        let hy = (start.y - end.y) / 2
        // Radii too small to span the chord grow until they just do, as SVG says.
        let grow = max(1, (hx * hx) / (rx * rx) + (hy * hy) / (ry * ry)).squareRoot()
        let rx = rx * grow
        let ry = ry * grow
        let numerator = rx * rx * ry * ry - rx * rx * hy * hy - ry * ry * hx * hx
        let denominator = rx * rx * hy * hy + ry * ry * hx * hx
        let scale = (max(0, numerator) / denominator).squareRoot()
        let centreX = scale * (rx * hy / ry) + (start.x + end.x) / 2
        let centreY = scale * -(ry * hx / rx) + (start.y + end.y) / 2
        let from = atan2((start.y - centreY) / ry, (start.x - centreX) / rx)
        var sweep = atan2((end.y - centreY) / ry, (end.x - centreX) / rx) - from
        if sweep < 0 { sweep += 2 * .pi }
        // Core Graphics' own arc is built of quarter-turn curves, which stray past 0.01 pt beyond r 37.
        let pieces = max(1, Int((sweep / (.pi / 6)).rounded(.up)))
        let step = sweep / Double(pieces)
        let handle = 4 / 3 * tan(step / 4)
        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: centreX + rx * cos(angle), y: centreY + ry * sin(angle))
        }
        func tangent(_ angle: Double) -> CGPoint { CGPoint(x: -rx * sin(angle), y: ry * cos(angle)) }
        for i in 0..<pieces {
            let a = from + Double(i) * step
            let b = i == pieces - 1 ? from + sweep : a + step
            let pa = point(a)
            let pb = i == pieces - 1 ? end : point(b)
            let ta = tangent(a)
            let tb = tangent(b)
            addCurve(
                to: pb, control1: CGPoint(x: pa.x + handle * ta.x, y: pa.y + handle * ta.y),
                control2: CGPoint(x: pb.x - handle * tb.x, y: pb.y - handle * tb.y))
        }
    }
}
