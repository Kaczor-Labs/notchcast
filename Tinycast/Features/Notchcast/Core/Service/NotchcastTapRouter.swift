import CoreGraphics
import Foundation
import Synchronization

/// The tap thread's half of the hub: routes one event to its consumers without the main actor.
final class NotchcastTapRouter: Sendable {
    enum Outcome: Sendable, Equatable {
        case pass
        case swallow
        case reenable([UUID])
    }

    struct Consumer: Sendable {
        let id: UUID
        let mask: CGEventMask
        let skipsSynthetic: Bool
        let synchronous: NotchcastTap.Synchronous?
    }

    private struct State {
        var active = true
        var consumers: [Consumer]
    }

    private let state: Mutex<State>
    private let syntheticTag: Int64
    private let onDisabled: @Sendable ([UUID]) -> Void
    private let onEvent: @Sendable (NotchcastTapEvent, [UUID]) -> Void

    init(
        consumers: [Consumer], syntheticTag: Int64,
        onDisabled: @escaping @Sendable ([UUID]) -> Void,
        onEvent: @escaping @Sendable (NotchcastTapEvent, [UUID]) -> Void
    ) {
        state = Mutex(State(consumers: consumers))
        self.syntheticTag = syntheticTag
        self.onDisabled = onDisabled
        self.onEvent = onEvent
    }

    var isActive: Bool { state.withLock { $0.active } }

    func update(_ consumers: [Consumer]) {
        state.withLock { $0.consumers = consumers }
    }

    func deactivate() {
        state.withLock { $0.active = false }
    }

    /// The tap thread calls this once the tap is live again, with the ids the disable notice named.
    func reenabled(_ ids: [UUID]) {
        onDisabled(ids)
    }

    func receive(type: CGEventType, event: CGEvent) -> Outcome {
        guard let consumers = state.withLock({ $0.active ? $0.consumers : nil }) else { return .pass }
        if NotchcastTapPolicy.isDisabledNotice(type) { return .reenable(consumers.map(\.id)) }
        let bit = NotchcastTapPolicy.mask(for: type)
        let synthetic = event.getIntegerValueField(.eventSourceUserData) == syntheticTag
        var swallowed = false
        var observers: [UUID] = []
        for consumer in consumers where consumer.mask & bit != 0 && !(synthetic && consumer.skipsSynthetic) {
            if let handler = consumer.synchronous {
                if handler(type, event) == .swallow { swallowed = true }
            } else {
                observers.append(consumer.id)
            }
        }
        if !observers.isEmpty {
            onEvent(NotchcastTapEvent(type: type, event: event, syntheticTag: syntheticTag), observers)
        }
        return swallowed ? .swallow : .pass
    }
}
