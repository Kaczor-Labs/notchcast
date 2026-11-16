import Foundation

/// The open island's hairline: one device pixel inside the outline, fading in as the island grows.
enum IslandKeyline {
    /// Points of growth past the rest pill that bring the line to full strength.
    static let ramp = 16.0

    static func width(scale: Double) -> Double { 1 / max(scale, 1) }

    static func strength(growth: Double, enabled: Bool) -> Double {
        enabled ? min(max(growth / ramp, 0), 1) : 0
    }
}
