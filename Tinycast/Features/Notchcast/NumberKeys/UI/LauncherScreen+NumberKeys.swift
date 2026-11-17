import Foundation

extension LauncherScreen {
    /// The ⌘-digit keycap of each result an add-on maps a digit to, keyed by entry id.
    var numberKeySlots: [String: Character] {
        guard let digitRow = Self.digitRow else { return [:] }
        let entryRows = rows.indices.filter { if case .entry = rows[$0] { true } else { false } }
        let caps = LauncherNumberKeys.keycaps { digitRow($0, vm.query, entryRows) }
        var slots: [String: Character] = [:]
        for (row, cap) in caps {
            if rows.indices.contains(row), case .entry(let app) = rows[row] { slots[app.id] = cap }
        }
        return slots
    }
}
