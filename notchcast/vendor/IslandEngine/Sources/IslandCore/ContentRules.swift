import Foundation

/// A value within this of 1 draws as exactly 1.
let settledShare = 1e-3

/// How far, in device pixels, a resting slot may sit off the pixel grid and still be put on it.
let gridSnap = 0.05

/// How far a bubble slot's band clip reaches past the slot on each side, in points on screen.
let bandReach = 400.0

/// Space between the expanded regions' columns.
public let expandedColumnGap = 10.0

func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}

/// A value within `settledShare` of 1 is 1, so a spring's last hair never leaves a slot soft.
func full(_ value: Double) -> Double {
    abs(1 - value) < settledShare ? 1 : value
}

/// A layer's opacity at `presence` under reduced motion: out by halfway, in from there.
func reducedOpacity(_ presence: Double) -> Double {
    min(1, max(0, presence * 2 - 1))
}

/// Whether `a` exists and matches `b` in every field.
func sameTarget(_ a: ShapeTarget?, _ b: ShapeTarget) -> Bool {
    guard let a else { return false }
    return a == b
}

/// A layer's presence `delay` seconds back; a layer that came back while showing shows no more.
func lagged(_ layer: AnimatedValue?, _ t: Double, delay: Double, rejoined: Bool) -> Double? {
    guard let layer else { return nil }
    let behind = layer.value(at: t - delay)
    return rejoined ? min(behind, layer.value(at: t)) : behind
}

/// An entering layer's trailing-slot presence: its own value, the layer's held back, or the layer's.
func enteringTrailing(
    _ layer: AnimatedValue?, own: AnimatedValue?, delay: Double, _ t: Double, rejoined: Bool
) -> Double {
    if let own { return full(clamp01(own.value(at: t))) }
    let value = delay > 0 ? lagged(layer, t, delay: delay, rejoined: rejoined) : layer?.value(at: t)
    return full(clamp01(value ?? 1))
}

/// What is left of an entering blur at presence `pres`, 1 to 0, gone `clear` presence early.
func blurLeft(_ pres: Double, clear: Double) -> Double {
    let p = clamp01(pres)
    if clear <= 0 { return 1 - p }
    return clear >= 1 ? 0 : max(0, 1 - p - clear) / (1 - clear)
}

/// How a bubble's content leaves on `exit`: a cut when its response is 0, else that spring.
func bubbleCut(_ exit: DelayedSpring) -> Transition {
    exit.response <= 0 ? .tween(duration: 1e-4, delay: exit.delay) : .spring(exit.spring, delay: exit.delay)
}

/// A measured width that keeps `previous` unless it moved by 0.05 points or more.
public func stableWidth(_ next: Double, previous: Double?) -> Double {
    if let previous, abs(next - previous) < 0.05 { return previous }
    return next
}

/// The width a slot is cut to when its content is wider than `room`, or nil when it fits.
public func fittedWidth(natural: Double, room: Double) -> Double? {
    natural > room + 0.25 ? room : nil
}

/// The widths of the expanded grid's leading and trailing columns.
public struct ExpandedColumns: Sendable, Equatable {
    public var leading: Double
    public var trailing: Double
}

/// Equal side columns as wide as the wider side, unless that would cut the center short.
/// Widths are the regions' used widths; `innerWidth` is the expanded slot's content box.
public func expandedColumns(
    leading: Double, center: Double, trailing: Double, innerWidth: Double
) -> ExpandedColumns {
    func natural(_ width: Double) -> Double { width.rounded(.up) + 1 }
    let l = natural(leading)
    let t = natural(trailing)
    let c = natural(center)
    let room = innerWidth - 2 * expandedColumnGap
    let side = max(l, t)
    return c + 2 * side <= room ? ExpandedColumns(leading: side, trailing: side) : ExpandedColumns(leading: l, trailing: t)
}

/// Where the expanded center region sits: its top below the sensor, and its sideways shift.
public struct ExpandedCenterPlacement: Sendable, Equatable {
    public var top: Double
    public var shift: Double
}

/// The expanded center region's top (the sensor's bottom edge) and its shift for uneven padding.
public func expandedCenterPlacement(metrics: IslandMetrics) -> ExpandedCenterPlacement {
    let e = metrics.expanded
    let sensorBottom = metrics.top + metrics.idle.height
    let top = max(0, sensorBottom - (e.top + e.padding.top)) + e.centerTop
    let shift = ((e.padding.trailing ?? e.padding.side) - e.padding.side) / 2
    return ExpandedCenterPlacement(top: top, shift: shift)
}

/// Gamma-encoded Rec. 709 luma (0 to 1) of a CSS colour in hex or rgb() form, else nil.
public func colourLuma(_ colour: String) -> Double? {
    let value = colour.unicodeScalars.map { isJavaScriptWhitespace($0) ? " " : String($0) }
        .joined().trimmingCharacters(in: CharacterSet(charactersIn: " ")).lowercased()
    var rgb: [Double]?
    if value.hasPrefix("#") {
        let digits = Array(value.dropFirst())
        let hex = digits.allSatisfy { $0.isASCII && $0.isHexDigit }
        // Three or six colour digits, each optionally followed by two of alpha.
        if hex, [3, 5, 6, 8].contains(digits.count) {
            let colourDigits = digits.count <= 5 ? digits.prefix(3).flatMap { [$0, $0] } : Array(digits.prefix(6))
            rgb = stride(from: 0, to: 6, by: 2).map { Double(Int(String(colourDigits[$0...$0 + 1]), radix: 16)!) }
        }
    }
    let number = "([0-9]+(?:\\.[0-9]+)?)"
    if let pattern = try? Regex("^rgba?\\( *\(number)[ ,]+\(number)[ ,]+\(number)"),
        let match = try? pattern.prefixMatch(in: value)
    {
        rgb = (1...3).map { Double(match.output[$0].substring.map(String.init) ?? "") ?? .nan }
    }
    guard let rgb else { return nil }
    return (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255
}

/// Keyline alpha over a page of `luma`: full, then log-linear through `keylineFade`, then to none.
public func keylineAlphaFor(_ luma: Double, metrics: IslandMetrics) -> Double {
    let k = metrics.keyline
    if luma.isNaN { return 0 }
    if luma >= k.noneFrom { return 0 }
    if luma <= k.fullUntil { return k.alpha }
    var from = KeylineFadePoint(luma: k.fullUntil, share: 1)
    for point in keylineFade {
        // With `fullUntil` or `noneFrom` overridden past a point, it would bend the fade backwards.
        if point.luma <= from.luma || point.luma >= k.noneFrom { continue }
        if luma <= point.luma {
            let t = (luma - from.luma) / (point.luma - from.luma)
            return k.alpha * from.share * pow(point.share / from.share, t)
        }
        from = point
    }
    return k.alpha * from.share * (1 - (luma - from.luma) / (k.noneFrom - from.luma))
}

/// The keyline's strength on a frame, dipping after a collapse that started at `dipAt`.
func keylineAt(
    _ frame: FrameGeometry, _ t: Double, keyline: Double, idle: Bool, leaving: Bool, dipAt: Double?,
    reduced: Bool, metrics m: IslandMetrics, motion: IslandMotion
) -> Double {
    if keyline <= 0 { return 0 }
    if idle && !leaving { return 0 }
    let grown = clamp01((frame.pill.width - m.idle.width) / max(m.keyline.ramp, 0.01))
    let expanded = 1 - m.keyline.expandedDim * frame.expansion
    var dip = 1.0
    if let dipAt, !reduced {
        let d = motion.keyline
        let since = t - dipAt
        if since >= 0 && since < d.dipAt {
            dip = 1 - (1 - d.dip) * (since / d.dipAt)
        } else if since >= d.dipAt && since < d.backAt {
            dip = d.dip + (1 - d.dip) * ((since - d.dipAt) / (d.backAt - d.dipAt))
        }
    }
    return keyline * grown * expanded * dip
}
