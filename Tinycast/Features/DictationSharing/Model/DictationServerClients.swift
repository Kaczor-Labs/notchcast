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
        await withTaskGroup(of: Void.self) { group in
            var reply: Task<Void, Never>?
            var disconnected = false
            group.addImmediateTask { @MainActor in
                await left()
                disconnected = true
                reply?.cancel()
            }
            guard !disconnected else { return }
            let workTask = Task {
                let value = await work()
                guard !Task.isCancelled else { return }
                await send(value)
            }
            reply = workTask
            await withTaskCancellationHandler {
                await workTask.value
                group.cancelAll()
            } onCancel: {
                workTask.cancel()
            }
        }
    }
}
