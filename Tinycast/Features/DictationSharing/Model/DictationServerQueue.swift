import Foundation

/// Shared-model requests take turns in arrival order, and none starts while the user dictates.
@MainActor
final class DictationServerQueue {
    struct Full: Error {}

    private let capacity: Int
    private var holder = false
    private var userDictating = false
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(capacity: Int) { self.capacity = capacity }

    var waitingCount: Int { waiting.count }
    var isHeld: Bool { holder }

    func setUserDictating(_ dictating: Bool) {
        userDictating = dictating
        admitNext()
    }

    /// Returns holding the turn, which the caller gives back with `leave()`.
    func enter() async throws {
        try Task.checkCancellation()
        if !holder, !userDictating, waiting.isEmpty {
            holder = true
            return
        }
        guard waiting.count < capacity else { throw Full() }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting.append((id, $0)) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.withdraw(id) }
        }
    }

    func leave() {
        holder = false
        admitNext()
    }

    /// Runs after the append, since both happen on the main actor and the append does not suspend.
    private func withdraw(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func admitNext() {
        guard !holder, !userDictating, !waiting.isEmpty else { return }
        holder = true
        waiting.removeFirst().continuation.resume()
    }
}
