import Foundation

extension IslandController {
    /// What the island shows now, in the presenter's order; the palette hides the rest, the glance status.
    var accessibilityValue: String {
        if let level { return "\(level.label), \(level.readout)" }
        if panel?.isVisible == true { return "" }
        if let notice { return notice.spoken }
        if let glance { return "\(glance.title), \(glance.countdown)" }
        return statuses.map(\.label).joined(separator: ", ")
    }
}
