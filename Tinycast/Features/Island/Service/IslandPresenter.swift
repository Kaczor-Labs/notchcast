import AppKit
import Observation

/// Renders levels and the meeting expansion; notices, status and menu rows come later.
@MainActor
final class IslandPresenter: IslandPresenting {
    private var dwell = IslandLevelDwell()
    private var dwellTask: Task<Void, Never>?
    private weak var pill: IslandController?
    private var band: HUDPanel?
    private var bandShown = false
    private var observing = false
    private var expansion = IslandMeetingExpansion()
    private var expansionTask: Task<Void, Never>?
    private var occurrence: IslandMeetingExpansion.Occurrence?
    private weak var expandedPill: IslandController?

    func showLevel(_ level: IslandLevel) {
        if dwell.show(level, at: Self.now) {
            dwellTask?.cancel()
            dwellTask = endWhenDwelled(dwell.presentation)
            if !observing { observePlacement() }
        }
        place()
        updateExpansion()
    }

    /// The carded meeting the resting glance shows, or nil once its join window closes.
    func meetingChanged(_ occurrence: IslandMeetingExpansion.Occurrence?) {
        self.occurrence = occurrence
        if occurrence != nil, !observing { observePlacement() }
        updateExpansion()
    }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    #if DEBUG
    var presentations: Int { dwell.presentation }
    var expansions: Int { expansion.presentation }
    /// A scene's shorter expansion, so it settles inside the 9 s run.
    func previewExpansion(seconds: TimeInterval) { expansion = IslandMeetingExpansion(seconds: seconds) }
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
            self.updateExpansion()
        }
    }

    private func settleWhenExpanded(_ token: Int) -> Task<Void, Never> {
        Task { [weak self] in
            while let left = self?.expansion.remaining(token, at: Self.now) {
                try? await Task.sleep(for: .seconds(left))
                guard !Task.isCancelled else { return }
            }
            guard let self, self.expansion.presentation == token else { return }
            self.expansionTask = nil
            self.updateExpansion()
        }
    }

    private func updateExpansion() {
        let core = AppCore.shared
        if expansion.update(carded: occurrence, waiting: dwell.level != nil,
                            covered: core.palette.isVisible || core.isShowingDialog, at: Self.now) {
            expansionTask?.cancel()
            expansionTask = settleWhenExpanded(expansion.presentation)
        }
        if expansion.showing == nil {
            expansionTask?.cancel()
            expansionTask = nil
        }
        let pill = expansion.showing == nil ? nil : core.island.resting
        if expandedPill !== pill { expandedPill?.expanded = false }
        expandedPill = pill
        pill?.expanded = true
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
                guard self.dwell.level != nil || self.occurrence != nil else { return }
                self.observePlacement()
                self.place()
                self.updateExpansion()
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

    isolated deinit {
        dwellTask?.cancel()
        expansionTask?.cancel()
    }
}
