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

    /// Keep watching for close until the reply finishes sending.
    static func answer<Value: Sendable>(
        _ work: @escaping @MainActor @Sendable () async -> Value,
        unless left: @escaping @MainActor @Sendable () async -> Void,
        send: @escaping @MainActor @Sendable (Value) async -> Void
    ) async {
        let reply = Task {
            let value = await work()
            guard !Task.isCancelled else { return }
            await send(value)
        }
        let watchClose: @MainActor @Sendable () async -> Void = {
            await left()
            reply.cancel()
        }
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask(operation: watchClose)
                await reply.value
                group.cancelAll()
            }
        } onCancel: {
            reply.cancel()
        }
    }
}
