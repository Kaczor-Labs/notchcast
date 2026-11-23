import Foundation

struct CleanerPlan: Sendable {
    let area: CleanerArea
    let items: [CleanerItem]
    let snapshots: [URL: CleanerSnapshot]

    var knownBytes: Int64 { items.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }
    var unknownCount: Int { items.count { $0.size == nil } }

    var defaultSelection: CleanerSelection {
        CleanerSelection(plan: self, checked: Set(items.filter { $0.standing == .recommended }.map(\.id)))
    }
}

struct CleanerSelection: Sendable, Equatable {
    private(set) var checked: Set<URL>

    init(plan: CleanerPlan, checked: Set<URL>) {
        self.checked = checked.intersection(plan.items.filter { $0.standing.isSelectable }.map(\.id))
    }

    mutating func set(_ id: URL, checked: Bool, in plan: CleanerPlan) {
        if checked, plan.items.contains(where: { $0.id == id && $0.standing.isSelectable }) {
            self.checked.insert(id)
        } else {
            self.checked.remove(id)
        }
    }
}
