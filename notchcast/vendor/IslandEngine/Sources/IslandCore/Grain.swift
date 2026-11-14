public enum ShadowGrain {
    public static let side = 32
    public static let alpha: [UInt8] = {
        var seed: UInt32 = 0x1c0de
        return (0..<(side * side)).map { _ in
            seed = seed &+ 0x6d2b79f5
            var x = (seed ^ (seed >> 15)) &* (1 | seed)
            x = (x &+ ((x ^ (x >> 7)) &* (61 | x))) ^ x
            return UInt8(truncatingIfNeeded: x ^ (x >> 14))
        }
    }()

    public static func changesAlpha(_ grain: IslandMetrics.Expanded.Shadow.Grain) -> Bool {
        grain.levels >= 510.0 / 256
    }

    public static func alpha(_ shade: UInt8, noise: UInt8, grain: IslandMetrics.Expanded.Shadow.Grain) -> UInt8 {
        guard grain.levels > 0 else { return shade }
        let gate = min(255, Int((Double(shade) / max(0.0001, grain.full)).rounded()))
        let scaled = gate * Int(noise) / 255
        // Gecko quantizes each arithmetic coefficient to 8.8 before clamping each result.
        let raised = min(255, (Int(shade) * 256 + scaled * Int(grain.levels * 256 / 255)) / 256)
        return UInt8(max(0, (raised * 256 - gate * Int(grain.levels * 256 / 510)) >> 8))
    }
}
