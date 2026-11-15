import CoreGraphics
import Foundation
import Observation

/// What the hub asks its session factory for; the live factory is `NotchcastTapThread`.
struct NotchcastTapSessionRequest {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
}

/// One installed tap. The hub creates a new session whenever its mask or options change.
protocol NotchcastTapSession: AnyObject {
    var mask: CGEventMask { get }
    var options: CGEventTapOptions { get }
    var router: NotchcastTapRouter { get }
    var isRunning: Bool { get }
    func stop()
}

/// The one shared event tap: installed only while something subscribes, gone with the last.
@MainActor
@Observable
final class NotchcastTapHub {
    /// Accessibility trust as last read; macOS announces no change, so `refreshPermission` rereads it.
    private(set) var isTrusted = false
    @ObservationIgnored private var taps: [UUID: NotchcastTap] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var session: (any NotchcastTapSession)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let syntheticTag: Int64
    @ObservationIgnored private let readTrust: @MainActor () -> Bool
    @ObservationIgnored private let makeSession: @MainActor (NotchcastTapSessionRequest) -> any NotchcastTapSession

    init(
        syntheticTag: Int64, isTrusted: @escaping @MainActor () -> Bool,
        makeSession: @escaping @MainActor (NotchcastTapSessionRequest) -> any NotchcastTapSession
    ) {
        self.syntheticTag = syntheticTag
        readTrust = isTrusted
        self.makeSession = makeSession
    }

    var subscriberCount: Int { order.count }
    var eventMask: CGEventMask { order.reduce(0) { $0 | (taps[$1]?.mask ?? 0) } }
    var isRunning: Bool { session?.isRunning == true }

    @discardableResult
    func subscribe(_ tap: NotchcastTap) -> UUID {
        precondition(tap.mask != 0)
        let id = UUID()
        taps[id] = tap
        order.append(id)
        reconcile()
        return id
    }

    func remove(_ id: UUID) {
        guard taps.removeValue(forKey: id) != nil else { return }
        order.removeAll { $0 == id }
        reconcile()
    }

    func stop() {
        taps.removeAll()
        order.removeAll()
        reconcile()
    }

    /// Restarts a tap that could not start for lack of trust; reading trust never prompts.
    func refreshPermission() {
        reconcile()
    }

    private func reconcile() {
        let trusted = readTrust()
        if isTrusted != trusted { isTrusted = trusted }
        guard !order.isEmpty, trusted else {
            endSession()
            return
        }
        let consumers = order.compactMap { id -> NotchcastTapRouter.Consumer? in
            guard let tap = taps[id] else { return nil }
            if case .synchronous(let handler) = tap.handler {
                return .init(id: id, mask: tap.mask, skipsSynthetic: tap.skipsSynthetic, synchronous: handler)
            }
            return .init(id: id, mask: tap.mask, skipsSynthetic: tap.skipsSynthetic, synchronous: nil)
        }
        let options = NotchcastTapPolicy.options(hasSynchronousConsumers: consumers.contains { $0.synchronous != nil })
        let mask = eventMask
        if let session, session.mask == mask, session.options == options, session.isRunning {
            session.router.update(consumers)
            return
        }
        endSession()
        generation += 1
        let current = generation
        let router = NotchcastTapRouter(
            consumers: consumers, syntheticTag: syntheticTag,
            onDisabled: { [weak self] in
                DispatchQueue.main.async { [weak self] in self?.resetSubscribers(generation: current) }
            },
            onEvent: { [weak self] event, ids in
                // One FIFO keeps event order without moving a CGEvent across isolation.
                DispatchQueue.main.async { [weak self] in self?.deliver(event, to: ids, generation: current) }
            })
        session = makeSession(NotchcastTapSessionRequest(mask: mask, options: options, router: router))
    }

    private func endSession() {
        session?.router.deactivate()
        session?.stop()
        session = nil
    }

    private func deliver(_ event: NotchcastTapEvent, to ids: [UUID], generation: Int) {
        guard generation == self.generation else { return }
        for id in ids {
            if case .observe(let handler) = taps[id]?.handler { handler(event) }
        }
    }

    private func resetSubscribers(generation: Int) {
        guard generation == self.generation else { return }
        for id in order { taps[id]?.reset?() }
    }
}
