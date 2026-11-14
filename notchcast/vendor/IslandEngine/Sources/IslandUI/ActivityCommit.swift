import SwiftUI

package struct IslandActivityCommit: Equatable, Sendable {
    package let id: UUID
    package let generation: Int
    package let model: ObjectIdentifier
    package let run: @MainActor @Sendable () -> Void

    package init(id: UUID, generation: Int, model: ObjectIdentifier, run: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.generation = generation
        self.model = model
        self.run = run
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.generation == rhs.generation && lhs.model == rhs.model
    }
}

package struct IslandActivityCommits: PreferenceKey {
    package static var defaultValue: [IslandActivityCommit] { [] }

    package static func reduce(value: inout [IslandActivityCommit], nextValue: () -> [IslandActivityCommit]) {
        value.append(contentsOf: nextValue())
    }
}
