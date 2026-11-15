import Foundation

extension IslandController {
    /// What the island shows now, in the presenter's order; the meeting glance hides status glyphs.
    var accessibilityValue: String {
        if let level { return "\(level.label), \(level.value.formatted(.percent))" }
        if let notice { return notice.text }
        if let glance { return "\(glance.title), \(glance.countdown)" }
        return statuses.map(\.label).joined(separator: ", ")
    }
}
