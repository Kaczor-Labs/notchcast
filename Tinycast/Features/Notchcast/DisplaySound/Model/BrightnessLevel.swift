import Foundation

/// One display's level: 0…1 drives the hardware, −0.25…0 dims the picture below it.
struct BrightnessLevel: Equatable, Sendable {
    static let step = 1.0 / 16
    static let extraDimmingRange = 0.25
    static let minimumPicture = 0.05

    let value: Double
    let softwareOnly: Bool

    init(_ value: Double, softwareOnly: Bool = false) {
        let minimum = softwareOnly ? 0 : -Self.extraDimmingRange
        self.value = value.isNaN ? 0 : min(max(value, minimum), 1)
        self.softwareOnly = softwareOnly
    }

    /// The level whose gamma factor is `picture`, so a floor maps back to a value.
    init(picture: Double, softwareOnly: Bool) {
        let position = (picture - Self.minimumPicture) / (1 - Self.minimumPicture)
        self.init(softwareOnly ? position : (position - 1) * Self.extraDimmingRange, softwareOnly: softwareOnly)
    }

    var hardware: Double { max(value, 0) }
    /// Rounds as the island's level readout does, so Settings and the HUD never disagree.
    var readout: String {
        value < 0 ? String(localized: "Dim", table: "NotchcastDisplaySound") : IslandLevel.readout(value)
    }
    var isDimmed: Bool { picture < 1 }

    var picture: Double {
        let position = softwareOnly ? value : 1 + min(value, 0) / Self.extraDimmingRange
        return Self.minimumPicture + (1 - Self.minimumPicture) * position
    }

    var range: ClosedRange<Double> { (softwareOnly ? 0 : -Self.extraDimmingRange)...1 }

    func refreshed(hardware: Double) -> Self {
        Self(hardware == 0 ? min(value, 0) : hardware)
    }

    func stepped(up: Bool, fine: Bool) -> Self {
        let delta = Self.step / (fine ? 4 : 1)
        let grid = value / delta
        let next = up ? floor(grid + 0.000001) + 1 : ceil(grid - 0.000001) - 1
        return Self(next * delta, softwareOnly: softwareOnly)
    }

    /// A display back from a connection gap never lands darker than the floor's picture.
    func reconnected() -> Self {
        let floor = BrightnessRecoveryPolicy.reconnectionDimFloor
        return picture >= floor ? self : Self(picture: floor, softwareOnly: softwareOnly)
    }
}
