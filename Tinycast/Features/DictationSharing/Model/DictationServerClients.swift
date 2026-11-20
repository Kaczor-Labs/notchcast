import Foundation

/// Connections being served, counted on the main actor so the cap cannot drift.
@MainActor
final class DictationServerClients {
    private let capacity: Int
    private(set) var active = 0

    init(capacity: Int) { self.capacity = capacity }

    func admit() -> Bool {
        guard active < capacity else { return false }
        active += 1
        return true
    }

    func release() { active -= 1 }

    /// The work's answer, or nil when `left` returns first; the other side is cancelled either way.
    static func answer<Value: Sendable>(
        _ work: @escaping @MainActor @Sendable () async -> Value, unless left: @escaping @Sendable () async -> Void
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await work() }
            group.addTask {
                await left()
                return nil
            }
            defer { group.cancelAll() }
            guard let first = await group.next() else { return nil }
            return first
        }
    }
}
