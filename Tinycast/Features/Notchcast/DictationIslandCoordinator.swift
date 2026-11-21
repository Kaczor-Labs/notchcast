import Foundation
import Observation

/// Shows a dictation session on the island in place of stock's capsule, and lends it the keyboard.
@MainActor
final class DictationIslandCoordinator {
    private var session = DictationIslandSession()
    private weak var controller: DictationPanelController?
    private var presenter: (any IslandPresenting)?
    private var covered: @MainActor () -> Bool = { false }
    private var copies: @MainActor () -> Bool = { false }
    private let now: @MainActor () -> TimeInterval
    private var shown: IslandNotice?

    init(now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func start(core: AppCore) {
        let dictation = core.dictationCoordinator
        attach(
            presenter: core.islandPresenter,
            covered: { [weak core] in core.map { $0.palette.isVisible || $0.isShowingDialog } ?? false },
            copies: { [weak core, weak dictation] in
                dictation?.field == nil && core?.settings.dictationDestination.pastes == false
            })
        let stock = dictation.showMessage
        dictation.showMessage = { [weak self] text, tone in
            if self?.message(text) != true { stock(text, tone) }
        }
        dictation.didReset = { [weak self] in self?.reset(completed: $0) }
        let extras = core.dictationExtras
        extras.cleaningUp = { [weak self] in self?.cleaningUp() }
        extras.cleanupFailed = { [weak self] in self?.cleanupFailed() ?? false }
        extras.delivered = { [weak self] in self?.delivered(empty: $0) }
    }

    /// The seam a Debug scene drives too, with its own presenter and no microphone.
    func attach(presenter: any IslandPresenting, covered: @escaping @MainActor () -> Bool,
                copies: @escaping @MainActor () -> Bool) {
        self.presenter = presenter
        self.covered = covered
        self.copies = copies
        DictationPanelController.stand = { [weak self] in self?.stand(in: $0) }
    }

    /// `show()` returns before stock resets the capsule's state, so the stand-in resets it.
    private func stand(in controller: DictationPanelController) {
        self.controller = controller
        controller.state.phase = .listening
        controller.state.levels = Array(repeating: 0, count: controller.state.levels.count)
        clear()
        session.begin(copies: copies(), at: now())
        post()
        presenter?.holdKeys { [weak self] key in
            switch key {
            case .accept: self?.controller?.onAccept?()
            case .cancel: self?.controller?.onCancel?()
            }
        }
        watch(generation: session.generation)
    }

    /// Re-arms after every change while its session lives; levels arrive about 20 times a second.
    private func watch(generation: Int) {
        guard let state = controller?.state, session.generation == generation,
            session.phase == .recording || session.phase == .transcribing
        else { return }
        withObservationTracking {
            _ = state.phase
            _ = state.levels
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed(generation: generation) }
        }
    }

    private func changed(generation: Int) {
        guard let state = controller?.state, session.generation == generation else { return }
        if state.phase == .transcribing ? session.transcribe() : session.hear(levels: state.levels, at: now()) {
            post()
        }
        watch(generation: generation)
    }

    func cleaningUp() {
        if session.cleanUp() { post() }
    }

    /// True when the island reports the raw paste; false leaves the sentence to the caller.
    func cleanupFailed() -> Bool { session.cleanupFailed(covered: covered()) }

    func delivered(empty: Bool) {
        session.delivered(empty: empty)
        presenter?.holdKeys(nil)
    }

    /// True when the island takes stock's report in place of its sentence under the island.
    func message(_ text: String) -> Bool { session.message(text, covered: covered()) }

    func reset(completed: Bool) {
        guard session.isLive else { return }
        let settles = session.end(completed: completed)
        presenter?.holdKeys(nil)
        guard completed else { return clear() }
        guard settles else { return }
        let generation = session.generation
        // One hop later, so stock's report raised right after `reset` in the same turn is counted.
        Task { @MainActor [weak self] in self?.settle(generation: generation) }
    }

    private func settle(generation: Int) {
        if let outcome = session.settle(generation: generation, covered: covered()) {
            shown = IslandNotice(dictation: outcome)
            presenter?.post(IslandNotice(dictation: outcome), onTap: nil)
        } else if !session.isLive {
            clear()
        }
    }

    private func clear() {
        guard shown != nil else { return }
        shown = nil
        presenter?.end(notice: IslandNotice.dictationID)
    }

    private func post() {
        guard let notice = IslandNotice(dictation: session), notice != shown else { return }
        shown = notice
        presenter?.post(notice, onTap: nil)
    }

    #if DEBUG
    var phase: DictationIslandSession.Phase { session.phase }
    var holdsKeys: Bool { session.holdsKeys }
    #endif
}
