/// JavaScript's `Math.max` of two numbers: NaN if either is, and +0 above -0.
func jsMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    if a == b { return a.sign == .minus ? b : a }
    return a > b ? a : b
}

/// JavaScript's `Math.min` of two numbers: NaN if either is, and -0 below +0.
func jsMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    if a == b { return a.sign == .minus ? a : b }
    return a < b ? a : b
}

/// JavaScript's `Math.round`: the nearest integer, halves toward +∞, -0 for -0.5 up to 0.
/// Adding 0.5 first rounds 0.49999999999999994 up, so the half is judged on the exact fraction.
package func jsRound(_ value: Double) -> Double {
    guard value.isFinite else { return value }
    let floor = value.rounded(.down)
    let rounded = value - floor >= 0.5 ? floor + 1 : floor
    return rounded == 0 && value.sign == .minus ? -0.0 : rounded
}
