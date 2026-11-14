import Foundation

/// The weight of the wide part for a slot blurred `sigma` points on screen: 0 when sharp.
public func skirtWeight(_ skirt: BlurSkirt?, sigma: Double, leaving: Bool) -> Double {
    guard let skirt, !(sigma <= 0) else { return 0 }
    let gain = leaving ? (skirt.exitGain ?? skirt.gain) : skirt.gain
    let tail = skirt.tail ?? 0
    let ending = tail > 0 ? jsMin(1, sigma / tail) : 1
    let weight = gain * pow(sigma, skirt.power ?? 2) - skirt.floor
    return jsMin(skirt.max, jsMax(0, weight)) * ending
}

/// How much of the weight the slot itself gives up.
public func skirtDim(_ skirt: BlurSkirt?) -> Double {
    guard let skirt else { return 1 }
    return jsMin(1, jsMax(0, skirt.dim ?? 1))
}

/// The copy's blur in its own units: `width` on screen through a scale of `scale`, never past 20 widths.
public func skirtBlur(_ skirt: BlurSkirt, scale: Double) -> Double {
    jsMin(skirt.width / jsMax(scale, 0.05), skirt.width * 20)
}
