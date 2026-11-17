import Foundation

/// The hairline inside the outline: Black's fades in as the island grows; Frosted's is its edge.
enum IslandKeyline {
    /// Points of growth past the rest pill that bring the line to full strength.
    static let ramp = 16.0

    /// Black's line is one device pixel; Frosted's edge is one point, as the glass needs it to read.
    static func width(scale: Double, look: IslandLook = .black) -> Double {
        look == .frosted ? 1 : 1 / max(scale, 1)
    }

    static func strength(growth: Double, enabled: Bool, resting: Double = 0) -> Double {
        enabled ? max(min(max(growth / ramp, 0), 1), resting) : 0
    }

    /// A Frosted pill keeps its edge at rest; on a notch the rest outline is the hardware.
    static func restingStrength(look: IslandLook, hasNotch: Bool) -> Double {
        look == .frosted && !hasNotch ? 1 : 0
    }
}
