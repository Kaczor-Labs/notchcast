import CoreGraphics
import Foundation

@MainActor
final class RecordingPresenter: IslandPresenting {
    var log: [String] = []

    func showLevel(_ level: IslandLevel) { log.append("level \(level.source) \(level.value)") }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { log.append("post \(notice.id) \(notice.text)") }
    func end(notice id: String) { log.append("end \(id)") }
    func setStatus(_ status: IslandStatus?, for id: String) { log.append("status \(id)") }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        log.append("menu \(owner) \(rows.count)")
    }
}

/// Stands in for NotchcastTapThread: no real tap is ever created on this Mac.
final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    private(set) var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }

    /// What NotchcastTapThread does when CGEvent.tapCreate fails: the session ends on its own.
    func failInstall() {
        isRunning = false
        router.ended()
    }
}

@MainActor
final class FakeSystem {
    var trusted = true
    var sessions: [FakeSession] = []
    var live: FakeSession? { sessions.last.flatMap { $0.isRunning ? $0 : nil } }

    func makeHub() -> NotchcastTapHub {
        NotchcastTapHub(syntheticTag: syntheticTag, isTrusted: { [unowned self] in trusted }) { [unowned self] in
            let session = FakeSession($0)
            sessions.append(session)
            return session
        }
    }
}

let syntheticTag: Int64 = 0x7E57

/// Drives the hub as the controller does: the whole ordered list on every change.
@MainActor
final class Subscriptions {
    let hub: NotchcastTapHub
    private(set) var list: [(id: UUID, tap: NotchcastTap)] = []

    init(_ hub: NotchcastTapHub) { self.hub = hub }

    @discardableResult
    func add(_ tap: NotchcastTap) -> UUID {
        let id = UUID()
        list.append((id, tap))
        hub.setSubscribers(list)
        return id
    }

    func remove(_ id: UUID) {
        list.removeAll { $0.id == id }
        hub.setSubscribers(list)
    }

    /// The controller re-adds a re-enabled tap under the token it always had.
    func insert(_ id: UUID, _ tap: NotchcastTap, at index: Int) {
        list.insert((id, tap), at: index)
        hub.setSubscribers(list)
    }

    func reverse() {
        list.reverse()
        hub.setSubscribers(list)
    }
}
