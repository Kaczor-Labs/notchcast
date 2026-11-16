import Foundation
import Observation

/// Mirrors the update the user started onto the island: a progress notice, then a tappable status.
@MainActor
final class IslandUpdateActivity {
    private unowned let core: AppCore
    private var started = false
    private var shown = IslandLiveState(update: .none)
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
        let presenter = core.islandPresenter
        let tap = tap(stage)
        if var notice = next.notice {
            if let dwell = next.noticeSeconds { notice.seconds = scaled(dwell) }
            presenter.post(notice, onTap: tap)
        } else {
            presenter.end(notice: IslandLiveState.id)
        }
        presenter.setStatus(next.status, for: IslandLiveState.id, onTap: tap)
    }

    /// Replaces the stock launch HUD; a version that did not install taps into Try Again.
    func report(_ report: UpdateCheckStore.InstallReport?) {
        let state: IslandLiveState
        var tap: (@MainActor () -> Void)?
        switch report {
        case .installed(let version):
            state = IslandLiveState(report: .installed(version: version.description))
        case .notInstalled(let version):
            state = IslandLiveState(report: .notInstalled)
            tap = { [weak self] in self?.offerRetry(version) }
        case nil:
            return
        }
        guard var notice = state.notice else { return }
        if let dwell = state.noticeSeconds { notice.seconds = scaled(dwell) }
        core.islandPresenter.post(notice, onTap: tap)
    }

    private func offerRetry(_ version: AppVersion) {
        Task { [weak self] in
            guard let core = self?.core else { return }
            let retry = await core.reportFailure(
                title: String(localized: "Update failed"),
                message: String(
                    localized: """
                        Tinycast \(version.description) could not be installed. \
                        Check for updates to try again.
                        """),
                symbol: "arrow.down.circle", recovery: String(localized: "Try Again"))
            if retry { core.updateCoordinator.checkForUpdates() }
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
        case .installing(_, let phase): .installing(text: phase.message, progress: phase.fraction)
        case .readyToRelaunch: .ready
        case .failed: .failed
        }
    }
}
