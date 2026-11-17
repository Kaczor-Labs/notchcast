import Foundation

/// A display's gamma ramp as read before any dimming, so putting it back is bit-exact.
struct BrightnessGamma: Equatable, Sendable {
    let red: [Float]
    let green: [Float]
    let blue: [Float]

    func scaled(_ factor: Double) -> Self {
        guard factor < 1 else { return self }
        let factor = Float(max(factor, 0))
        return Self(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }
}
