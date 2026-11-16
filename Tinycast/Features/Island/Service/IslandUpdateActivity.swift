import Foundation
import Observation

/// Mirrors the update the user started onto the island: a progress notice, then a tappable status.
@MainActor
final class IslandUpdateActivity {
    private unowned let core: AppCore
    private var started = false
    private var shown = IslandLiveState(update: .none)
    private var endTask: Task<Void, Never>?
    #if DEBUG
    private var previewStage: UpdateCoordinator.Stage?
    private var previewSeconds: TimeInterval?
    #endif

    init(core: AppCore) { self.core = core }

    func start() {
        guard !started else { return }
        started = true
        observe()
    }

    private var stage: UpdateCoordinator.Stage {
        #if DEBUG
        if let previewStage { return previewStage }
        #endif
        return core.updateCoordinator.stage
    }

    private func observe() {
        let stage = withObservationTracking { self.stage } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        apply(stage)
    }

    #if DEBUG
    /// A scene's stage and notice dwell, so no download runs and the run fits its 9 s.
    func preview(_ stage: UpdateCoordinator.Stage?, seconds: TimeInterval? = nil) {
        previewStage = stage
        previewSeconds = seconds
        apply(self.stage)
    }
    #endif

    private func apply(_ stage: UpdateCoordinator.Stage) {
        let next = IslandLiveState(update: Self.update(stage))
        guard next != shown else { return }
        shown = next
        endTask?.cancel()
        endTask = nil
        let presenter = core.islandPresenter
        let tap = tap(stage)
        if let notice = next.notice { presenter.post(notice, onTap: tap) } else { presenter.end(notice: IslandLiveState.id) }
        presenter.setStatus(next.status, for: IslandLiveState.id, onTap: tap)
        guard let dwell = next.noticeSeconds else { return }
        let seconds = scaled(dwell)
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.endTask = nil
            self.core.islandPresenter.end(notice: IslandLiveState.id)
        }
    }

    private func scaled(_ seconds: TimeInterval) -> TimeInterval {
        #if DEBUG
        if let previewSeconds { return previewSeconds }
        #endif
        return seconds
    }

    private func tap(_ stage: UpdateCoordinator.Stage) -> (@MainActor () -> Void)? {
        switch stage {
        case .readyToRelaunch:
            { [weak self] in self?.core.paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true) }
        case .failed:
            { [weak self] in self?.core.updateCoordinator.showFailure() }
        case .idle, .checking, .available, .installing:
            nil
        }
    }

    private static func update(_ stage: UpdateCoordinator.Stage) -> IslandLiveState.Update {
        switch stage {
        case .idle, .checking, .available: .none
        case .installing(_, let phase): .installing(text: phase.message, progress: phase.fraction ?? 1)
        case .readyToRelaunch: .ready
        case .failed: .failed
        }
    }

    isolated deinit { endTask?.cancel() }
}
