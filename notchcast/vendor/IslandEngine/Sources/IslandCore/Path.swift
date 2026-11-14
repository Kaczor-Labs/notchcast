import Foundation

public struct Vec: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Circle: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var r: Double

    public init(x: Double, y: Double, r: Double) {
        self.x = x
        self.y = y
        self.r = r
    }
}

/// Corner shape: semi-axes along the horizontal and vertical edges, and the superellipse exponent.
public struct CornerShape: Sendable, Hashable {
    public var rx: Double
    public var ry: Double
    public var exponent: Double
    /// Continuous-corner smoothing, 0 to 1. Above 0 the corner is an arc of radius `rx` with eased
    /// transitions, and `ry` and `exponent` are ignored.
    public var smoothing: Double

    public init(rx: Double, ry: Double, exponent: Double, smoothing: Double = 0) {
        self.rx = rx
        self.ry = ry
        self.exponent = exponent
        self.smoothing = smoothing
    }
}

public struct BridgeOptions: Sendable, Hashable {
    /// Handle length factor for the connecting curves.
    public var handleSize: Double
    /// 0 to 1. How far round each circle the neck attaches. 0 pinches the neck to a line.
    public var spread: Double
    /// Gap between the circles' edges past which there is no bridge.
    public var maxGap: Double
    /// How the neck thins toward `maxGap`: 1.5 fades it to a hairline, lower keeps it until it breaks.
    public var power: Double

    public init(handleSize: Double, spread: Double, maxGap: Double, power: Double = 1.5) {
        self.handleSize = handleSize
        self.spread = spread
        self.maxGap = maxGap
        self.power = power
    }
}

/// An outline of the island, in the same drawing commands the web engine writes to its SVG.
///
/// Corners are continuous: a circular arc in the middle, and on each side a cubic that eases the
/// curvature in from the straight edge. `smoothing` sets how much of the arc the transitions take.
public struct IslandPath: Sendable, Equatable {
    public enum Element: Sendable, Equatable {
        case move(Vec)
        case line(Vec)
        case quad(control: Vec, to: Vec)
        case cubic(control1: Vec, control2: Vec, to: Vec)
        /// An SVG elliptical arc with no rotation, the small arc, swept clockwise on screen.
        case arc(rx: Double, ry: Double, to: Vec)
        case close
    }

    public var elements: [Element]

    public init(_ elements: [Element] = []) {
        self.elements = elements
    }

    public var isEmpty: Bool { elements.isEmpty }
}

private struct EdgeEase {
    /// Distance from the corner, along the edge, where the curve leaves it.
    var p: Double
    /// Bezier handle lengths along the edge, from `p` toward the corner.
    var a: Double
    var b: Double
    /// The arc's end on this side: distance from the corner along the edge, and in from it.
    var along: Double
    var across: Double

    init(r: Double, smoothing: Double, room: Double) {
        // Only as much smoothing as this edge has room for: the curve may use half its length.
        let s = max(0, min(smoothing, room / r - 1))
        let angle = (Double.pi / 4) * s
        p = (1 + s) * r
        along = r * (1 - sin(angle))
        across = r * (1 - cos(angle))
        let c = r * tan(angle / 2) * cos(angle)
        b = max(0, (p - c - along) / 3)
        a = 2 * b
    }
}

private func sign(_ value: Double) -> Double {
    value > 0 ? 1 : value < 0 ? -1 : 0
}

private func polar(_ c: Vec, _ angle: Double, _ length: Double) -> Vec {
    Vec(x: c.x + length * cos(angle), y: c.y + length * sin(angle))
}

// Segments per corner when the corner isn't a circular arc.
private let superellipseSegments = 24

extension IslandPath {
    /// A rectangle with continuous corners of radius `radius`, drawn clockwise from the top edge.
    /// `leading` is the two left corners' radius, and defaults to `radius`.
    public static func continuousRect(
        x: Double, y: Double, width: Double, height: Double,
        radius: Double, smoothing: Double, leading: Double? = nil
    ) -> IslandPath {
        let w = max(0, width)
        let h = max(0, height)
        if w == 0 || h == 0 { return IslandPath() }
        let r = max(0, min(radius, w / 2, h / 2))
        let rl = max(0, min(leading ?? radius, w / 2, h / 2))
        if r < 1e-3, rl < 1e-3 {
            return IslandPath([
                .move(Vec(x: x, y: y)), .line(Vec(x: x + w, y: y)), .line(Vec(x: x + w, y: y + h)),
                .line(Vec(x: x, y: y + h)), .close,
            ])
        }
        let across = EdgeEase(r: r, smoothing: smoothing, room: w / 2)
        let down = EdgeEase(r: r, smoothing: smoothing, room: h / 2)
        let acrossL = rl == r ? across : EdgeEase(r: rl, smoothing: smoothing, room: w / 2)
        let downL = rl == r ? down : EdgeEase(r: rl, smoothing: smoothing, room: h / 2)

        func point(_ k: Vec, _ u: Vec, _ du: Double, _ v: Vec, _ dv: Double) -> Vec {
            Vec(x: k.x + u.x * du + v.x * dv, y: k.y + u.y * du + v.y * dv)
        }
        // `u` points back along the edge the path arrives on, `v` along the edge it leaves on.
        func corner(_ k: Vec, _ u: Vec, _ v: Vec, _ inc: EdgeEase, _ out: EdgeEase, _ rc: Double) -> [Element] {
            [
                .line(point(k, u, inc.p, v, 0)),
                .cubic(
                    control1: point(k, u, inc.p - inc.a, v, 0),
                    control2: point(k, u, inc.p - inc.a - inc.b, v, 0),
                    to: point(k, u, inc.along, v, inc.across)
                ),
                .arc(rx: rc, ry: rc, to: point(k, v, out.along, u, out.across)),
                .cubic(
                    control1: point(k, v, out.p - out.a - out.b, u, 0),
                    control2: point(k, v, out.p - out.a, u, 0),
                    to: point(k, v, out.p, u, 0)
                ),
            ]
        }
        let right = x + w
        let bottom = y + h
        return IslandPath(
            [.move(Vec(x: x + acrossL.p, y: y))]
                + corner(Vec(x: right, y: y), Vec(x: -1, y: 0), Vec(x: 0, y: 1), across, down, r)
                + corner(Vec(x: right, y: bottom), Vec(x: 0, y: -1), Vec(x: -1, y: 0), down, across, r)
                + corner(Vec(x: x, y: bottom), Vec(x: 1, y: 0), Vec(x: 0, y: -1), acrossL, downL, rl)
                + corner(Vec(x: x, y: y), Vec(x: 0, y: 1), Vec(x: 1, y: 0), downL, acrossL, rl)
                + [.close]
        )
    }

    /// One quadrant centred at (cx, cy), starting at angle `from` (radians, clockwise on screen).
    private static func cornerQuadrant(cx: Double, cy: Double, _ c: CornerShape, from: Double) -> [Element] {
        if c.rx <= 0 || c.ry <= 0 { return [] }
        if abs(c.exponent - 2) < 1e-3 {
            let end = from + Double.pi / 2
            return [.arc(rx: c.rx, ry: c.ry, to: Vec(x: cx + c.rx * cos(end), y: cy + c.ry * sin(end)))]
        }
        let power = 2 / c.exponent
        return (1...superellipseSegments).map { i in
            let angle = from + (Double.pi / 2) * (Double(i) / Double(superellipseSegments))
            let cosine = cos(angle)
            let sine = sin(angle)
            return .line(Vec(
                x: cx + c.rx * sign(cosine) * pow(abs(cosine), power),
                y: cy + c.ry * sign(sine) * pow(abs(sine), power)
            ))
        }
    }

    /// A rectangle with superellipse corners, drawn clockwise. Corner axes clamp to half each side.
    /// `leading` shapes the two left corners, and defaults to `corner`.
    public static func roundedRect(
        x: Double, y: Double, width: Double, height: Double,
        corner: CornerShape, leading: CornerShape? = nil
    ) -> IslandPath {
        if corner.smoothing > 0 {
            return continuousRect(
                x: x, y: y, width: width, height: height,
                radius: corner.rx, smoothing: corner.smoothing, leading: (leading ?? corner).rx
            )
        }
        let w = max(0, width)
        let h = max(0, height)
        if w == 0 || h == 0 { return IslandPath() }
        func clamped(_ k: CornerShape) -> CornerShape {
            CornerShape(rx: max(0, min(k.rx, w / 2)), ry: max(0, min(k.ry, h / 2)), exponent: k.exponent)
        }
        let c = clamped(corner)
        let l = leading.map(clamped) ?? c
        let r = x + w
        let b = y + h
        return IslandPath(
            [.move(Vec(x: x + l.rx, y: y)), .line(Vec(x: r - c.rx, y: y))]
                + cornerQuadrant(cx: r - c.rx, cy: y + c.ry, c, from: -Double.pi / 2)
                + [.line(Vec(x: r, y: b - c.ry))]
                + cornerQuadrant(cx: r - c.rx, cy: b - c.ry, c, from: 0)
                + [.line(Vec(x: x + l.rx, y: b))]
                + cornerQuadrant(cx: x + l.rx, cy: b - l.ry, l, from: Double.pi / 2)
                + [.line(Vec(x: x, y: y + l.ry))]
                + cornerQuadrant(cx: x + l.rx, cy: y + l.ry, l, from: Double.pi)
                + [.close]
        )
    }

    /// A capsule: round ends on the shorter side, semicircles unless `smoothing` eases the shoulders.
    public static func capsule(x: Double, y: Double, width: Double, height: Double, smoothing: Double = 0) -> IslandPath {
        let r = min(width, height) / 2
        return roundedRect(
            x: x, y: y, width: width, height: height,
            corner: CornerShape(rx: r, ry: r, exponent: 2, smoothing: smoothing)
        )
    }

    /// The gooey neck between two circles (a metaball bridge), as a closed path that overlaps both.
    /// The neck thins to nothing as the gap reaches `maxGap`, so the pinch-off has no pop.
    public static func bridge(_ a: Circle, _ b: Circle, _ options: BridgeOptions) -> IslandPath {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let d = hypot(dx, dy)
        if a.r <= 0 || b.r <= 0 || d <= abs(a.r - b.r) { return IslandPath() }
        let gap = d - a.r - b.r
        if gap >= options.maxGap { return IslandPath() }

        // Fade the spread to 0 across the last part of the reach so the neck pinches smoothly.
        let reach = max(0, gap) / options.maxGap
        let v = options.spread * pow(1 - reach, options.power)
        if v <= 1e-4 { return IslandPath() }

        var u1 = 0.0
        var u2 = 0.0
        if d < a.r + b.r {
            u1 = acos(min(1, max(-1, (a.r * a.r + d * d - b.r * b.r) / (2 * a.r * d))))
            u2 = acos(min(1, max(-1, (b.r * b.r + d * d - a.r * a.r) / (2 * b.r * d))))
        }
        let between = atan2(dy, dx)
        let maxSpread = acos(min(1, max(-1, (a.r - b.r) / d)))

        let angle1 = between + u1 + (maxSpread - u1) * v
        let angle2 = between - u1 - (maxSpread - u1) * v
        let angle3 = between + Double.pi - u2 - (Double.pi - u2 - maxSpread) * v
        let angle4 = between - Double.pi + u2 + (Double.pi - u2 - maxSpread) * v

        let ca = Vec(x: a.x, y: a.y)
        let cb = Vec(x: b.x, y: b.y)
        let p1 = polar(ca, angle1, a.r)
        let p2 = polar(ca, angle2, a.r)
        let p3 = polar(cb, angle3, b.r)
        let p4 = polar(cb, angle4, b.r)

        let total = a.r + b.r
        let handle = min(v * options.handleSize, hypot(p1.x - p3.x, p1.y - p3.y) / total) * min(1, (d * 2) / total)
        let h1 = polar(p1, angle1 - Double.pi / 2, a.r * handle)
        let h2 = polar(p2, angle2 + Double.pi / 2, a.r * handle)
        let h3 = polar(p3, angle3 + Double.pi / 2, b.r * handle)
        let h4 = polar(p4, angle4 - Double.pi / 2, b.r * handle)

        return IslandPath([
            .move(p1), .cubic(control1: h1, control2: h3, to: p3),
            .line(p4), .cubic(control1: h4, control2: h2, to: p2), .close,
        ])
    }

    /// A short pointed nub on circle `c`, aimed at `toward`, its tip `length` past the circle: what
    /// a split neck leaves on each end when it first snaps. Empty for a length under 0.01 pt.
    public static func cusp(_ c: Circle, toward: Vec, length: Double, base: Double = 0.5) -> IslandPath {
        let d = hypot(toward.x - c.x, toward.y - c.y)
        if c.r <= 0 || d < 1e-6 || length < 0.01 { return IslandPath() }
        let centre = Vec(x: c.x, y: c.y)
        let aim = atan2(toward.y - c.y, toward.x - c.x)
        let tip = polar(centre, aim, c.r + length)
        // The control points sit on the circle near the aim, which bends each side in toward the cap.
        return IslandPath([
            .move(polar(centre, aim + base, c.r)),
            .quad(control: polar(centre, aim + base * 0.25, c.r), to: tip),
            .quad(control: polar(centre, aim - base * 0.25, c.r), to: polar(centre, aim - base, c.r)),
            .line(centre), .close,
        ])
    }

    /// A rectangle with its corners cut at 45 degrees, legs `leg` long: the island's content mask.
    public static func chamfer(x: Double, y: Double, width: Double, height: Double, leg: Double) -> IslandPath {
        let w = max(0, width)
        let h = max(0, height)
        if w == 0 || h == 0 { return IslandPath() }
        let c = max(0, min(leg, w / 2, h / 2))
        let r = x + w
        let b = y + h
        return IslandPath([
            .move(Vec(x: x + c, y: y)), .line(Vec(x: r - c, y: y)), .line(Vec(x: r, y: y + c)),
            .line(Vec(x: r, y: b - c)), .line(Vec(x: r - c, y: b)), .line(Vec(x: x + c, y: b)),
            .line(Vec(x: x, y: b - c)), .line(Vec(x: x, y: y + c)), .close,
        ])
    }
}
