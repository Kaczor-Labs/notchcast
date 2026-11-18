import AppKit
import Observation

/// Shows stock Dictation on the island; its capsule stays only as the unseen Return and Esc catcher.
@MainActor
final class NotchcastDictationIsland {
    private weak var core: AppCore?
    private let presenter: any IslandPresenting
    private var session = DictationIslandSession()
    private var isWatching = false

    init(core: AppCore) {
        self.core = core
        presenter = core.islandPresenter
        core.dictationCoordinator.didFinish = { [weak self] pasted in
            self?.finished(pasted.map { $0 ? .pasted : .copied } ?? .noSpeech)
        }
        core.dictationCoordinator.didReset = { [weak self] in self?.ended(completed: $0) }
    }

    /// Dictation's panel is about to show: the island takes over what it would have drawn.
    func began(_ display: DictationDisplayState, capsule: NSPanel) {
        capsule.alphaValue = 0
        capsule.contentView = NSView()
        guard let core else { return }
        let pastes = core.dictationCoordinator.field != nil || core.settings.dictationDestination.pastes
        session.begin(copies: !pastes, at: ProcessInfo.processInfo.systemUptime)
        publish()
        if !isWatching { watch(display) }
    }

    func cleaningUp() {
        if session.cleanUp() { publish() }
    }

    private func finished(_ outcome: DictationIslandSession.Outcome) {
        if session.finish(outcome, covered: isCovered) { publish() }
    }

    /// Dictation's reset: a session that ran to its end without an outcome has failed.
    private func ended(completed: Bool) {
        if session.end(completed: completed, covered: isCovered) { publish() }
    }

    /// The launcher and a question hide the pill, and the stock report already says what failed.
    private var isCovered: Bool { core?.palette.isVisible == true || core?.isShowingDialog == true }

    private func publish() {
        if let notice = IslandNotice(dictation: session) {
            presenter.post(notice, onTap: nil)
        } else {
            presenter.end(notice: IslandNotice.dictationID)
        }
    }

    /// The capsule's own state carries the levels and the move to transcribing, so no hook feeds them.
    private func watch(_ display: DictationDisplayState) {
        isWatching = true
        withObservationTracking {
            _ = display.levels
            _ = display.phase
        } onChange: { [weak self, weak display] in
            Task { @MainActor in
                guard let self else { return }
                self.isWatching = false
                guard let display, self.session.isActive else { return }
                let changed = display.phase == .transcribing
                    ? self.session.transcribe()
                    : self.session.hear(Double(display.levels.max() ?? 0), at: ProcessInfo.processInfo.systemUptime)
                if changed { self.publish() }
                self.watch(display)
            }
        }
    }
}
