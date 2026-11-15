import AppKit
import Observation

/// Renders levels in the resting pill or the report slot; notices, status and menu rows come later.
@MainActor
final class IslandPresenter: IslandPresenting {
    private var dwell = IslandLevelDwell()
    private var dwellTask: Task<Void, Never>?
    private weak var pill: IslandController?
    private var band: HUDPanel?
    private var bandShown = false
    private var observing = false

    func showLevel(_ level: IslandLevel) {
        if dwell.show(level, at: Self.now) {
            dwellTask?.cancel()
            dwellTask = endWhenDwelled(dwell.presentation)
            if !observing { observePlacement() }
        }
        place()
    }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    #if DEBUG
    var presentations: Int { dwell.presentation }
    #endif

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Sleeps out the dwell, then again for whatever repeats added, so a burst never restarts it.
    private func endWhenDwelled(_ token: Int) -> Task<Void, Never> {
        Task { [weak self] in
            while let left = self?.dwell.remaining(token, at: Self.now) {
                try? await Task.sleep(for: .seconds(left))
                guard !Task.isCancelled else { return }
            }
            guard let self, self.dwell.presentation == token, self.dwell.level == nil else { return }
            self.place()
            self.dwellTask = nil
        }
    }

    private func place() {
        let core = AppCore.shared
        let placement = dwell.placement(palette: core.palette.isVisible, question: core.isShowingDialog)
        if placement != .band { dismissBand() }
        if placement != .pill { pill?.level = nil }
        switch (placement, dwell.level) {
        case (.band?, let level?):
            stack(IslandLevelArt(level, notch: false))
        case (.pill?, let level?):
            pill = core.island.resting
            pill?.level = level
        default:
            pill = nil
        }
    }

    /// The palette or a question can open mid-dwell, and the level must follow without restarting.
    private func observePlacement() {
        observing = true
        withObservationTracking {
            _ = AppCore.shared.palette.isVisible
            _ = AppCore.shared.isShowingDialog
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observing = false
                guard self.dwell.level != nil else { return }
                self.observePlacement()
                self.place()
            }
        }
    }

    private func stack(_ art: IslandLevelArt) {
        let band = band ?? makeBand(art.bandSize)
        (band.contentView as? IslandLevelBand)?.art = art
        guard !bandShown else { return }
        bandShown = true
        AppCore.shared.island.overlays.placeReport(band, screen: nil)
        if band.isVisible {
            band.cancelFade()
        } else {
            band.fadeIn(duration: Theme.Duration.enter) { band.orderFrontRegardless() }
        }
    }

    private func makeBand(_ size: CGSize) -> HUDPanel {
        let band = HUDPanel()
        band.setContentSize(size)
        band.contentView = IslandLevelBand(frame: CGRect(origin: .zero, size: size))
        self.band = band
        return band
    }

    private func dismissBand() {
        guard bandShown, let band else { return }
        bandShown = false
        band.fadeOut(duration: Theme.Duration.exit)
    }

    isolated deinit { dwellTask?.cancel() }
}
