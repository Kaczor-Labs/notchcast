import Foundation

/// One display's level: 0…1 drives the hardware, −0.25…0 (extra dimming) dims the picture below it.
struct BrightnessLevel: Equatable, Sendable {
    static let step = 1.0 / 16
    static let extraDimmingRange = 0.25
    static let minimumPicture = 0.05

    let value: Double
    let softwareOnly: Bool
    /// Off, a backlight's own minimum is the floor and the picture is never dimmed below it.
    let extraDimming: Bool

    init(_ value: Double, softwareOnly: Bool = false, extraDimming: Bool = true) {
        let minimum = softwareOnly || !extraDimming ? 0 : -Self.extraDimmingRange
        self.value = value.isNaN ? 0 : min(max(value, minimum), 1)
        self.softwareOnly = softwareOnly
        self.extraDimming = extraDimming
    }

    /// The level whose gamma factor is `picture`, so a floor maps back to a value.
    init(picture: Double, softwareOnly: Bool) {
        let position = (picture - Self.minimumPicture) / (1 - Self.minimumPicture)
        self.init(softwareOnly ? position : (position - 1) * Self.extraDimmingRange, softwareOnly: softwareOnly)
    }

    var hardware: Double { max(value, 0) }
    /// Rounds as the island's level readout does, so Settings and the HUD never disagree.
    var readout: String { IslandLevel.readout(value, in: range) }
    var isDimmed: Bool { picture < 1 }

    var picture: Double {
        let position = softwareOnly ? value : 1 + min(value, 0) / Self.extraDimmingRange
        return Self.minimumPicture + (1 - Self.minimumPicture) * position
    }

    var range: ClosedRange<Double> { (softwareOnly || !extraDimming ? 0 : -Self.extraDimmingRange)...1 }

    func refreshed(hardware: Double) -> Self {
        Self(hardware == 0 ? min(value, 0) : hardware, extraDimming: extraDimming)
    }

    func stepped(up: Bool, fine: Bool) -> Self {
        let delta = Self.step / (fine ? 4 : 1)
        let grid = value / delta
        let next = up ? floor(grid + 0.000001) + 1 : ceil(grid - 0.000001) - 1
        return Self(next * delta, softwareOnly: softwareOnly, extraDimming: extraDimming)
    }

    func allowing(extraDimming: Bool) -> Self {
        Self(value, softwareOnly: softwareOnly, extraDimming: extraDimming)
    }

    /// Software dimming is a display's only brightness, so only extra dimming is dropped.
    func withoutExtraDimming() -> Self {
        softwareOnly ? self : Self(hardware, extraDimming: extraDimming)
    }

    /// A display back from a connection gap is never darker than its backlight or the software floor.
    func reconnected() -> Self {
        let floor = BrightnessRecoveryPolicy.reconnectionDimFloor
        guard softwareOnly, picture < floor else { return withoutExtraDimming() }
        return Self(picture: floor, softwareOnly: true)
    }
}
