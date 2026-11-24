import Foundation

struct CleanerItem: Identifiable, Equatable, Sendable {
    enum Standing: Equatable, Sendable {
        case recommended
        case optional
        case heldBack(CleanerHoldBack)
        case locked(CleanerHoldBack)

        var isSelectable: Bool { self == .recommended || self == .optional }
    }

    let id: URL
    let area: CleanerArea
    let size: MeasuredSize?
    let standing: Standing
}

struct CleanerSnapshot: Equatable, Sendable {
    let parents: [CleanerFile.Identity]
    let entries: [URL: CleanerFile]
}
