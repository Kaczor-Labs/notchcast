import AppKit
import Observation

/// Renders levels, notices, status and the meeting expansion on the resting pill.
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
    private var notices = IslandNoticeQueue()
    private var noticeTask: Task<Void, Never>?
    private var statuses: [IslandStatus] = []
    private var noticeTaps: [String: @MainActor () -> Void] = [:]
    private var statusTaps: [String: @MainActor () -> Void] = [:]
    private(set) var menus: [Menu] = []
    private let now: @MainActor () -> TimeInterval
    private let sleep: @MainActor (TimeInterval) async throws -> Void

    /// A harness injects its own clock, so a dwell is checked exactly rather than against the wall.
    init(now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.now = now
        self.sleep = sleep
    }

    struct Menu {
        let owner: String
        let rows: [IslandMenuRow]
        let onSelect: @MainActor (String) -> Void
    }

    func showLevel(_ level: IslandLevel) {
        if dwell.show(level, at: now()) {
            dwellTask?.cancel()
            dwellTask = endWhenDwelled(dwell.presentation)
            if !observing { observePlacement() }
        }
        place()
        noticesChanged()
    }

    /// The carded meeting the resting glance shows, or nil once its join window closes.
    func meetingChanged(_ occurrence: IslandMeetingExpansion.Occurrence?) {
        self.occurrence = occurrence
        if occurrence != nil, !observing { observePlacement() }
        updateExpansion()
    }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        notices.post(notice, at: now())
        noticeTaps[notice.id] = onTap
        if !observing { observePlacement() }
        noticesChanged()
    }

    func end(notice id: String) {
        notices.end(id, at: now())
        noticeTaps[id] = nil
        noticesChanged()
    }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        statuses.removeAll { $0.id == id }
        statusTaps[id] = status == nil ? nil : onTap
        if let status { statuses.append(status) }
        AppCore.shared.island.resting?.statuses = statuses
    }

    /// A click on the resting pill acts on what it shows; the meeting glance hides status.
    var tap: (@MainActor () -> Void)? {
        if let notice = notices.notice { return noticeTaps[notice.id] }
        if AppCore.shared.island.resting?.glance != nil { return nil }
        return statuses.last.flatMap { statusTaps[$0.id] }
    }

    /// Hands notices and status to the resting pill without posting, so none re-announces.
    func restore(_ controller: IslandController, resting: Bool) {
        controller.notice = resting ? notices.notice : nil
        controller.statuses = resting ? statuses : []
    }

    /// A rebuild can add or drop the resting pill, which a notice's dwell waits for.
    func restingChanged() { noticesChanged() }

    /// An owner keeps its first registration's place, so replacing its rows never reorders the menu.
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        let index = menus.firstIndex { $0.owner == owner }
        switch (index, rows.isEmpty) {
        case (let index?, true): menus.remove(at: index)
        case (let index?, false): menus[index] = Menu(owner: owner, rows: rows, onSelect: onSelect)
        case (nil, false): menus.append(Menu(owner: owner, rows: rows, onSelect: onSelect))
        case (nil, true): return
        }
        AppCore.shared.island.pillMenu.refit(keepingSelection: true)
    }

    #if DEBUG
    var presentations: Int { dwell.presentation }
    var expansions: Int { expansion.presentation }
    /// A scene's shorter expansion, so it settles inside the 9 s run.
    func previewExpansion(seconds: TimeInterval) { expansion = IslandMeetingExpansion(seconds: seconds) }
    #endif

    /// Anything that keeps the pill's notice unseen pauses its dwell; the announcement follows the top.
    private func noticesChanged() {
        let time = now()
        let core = AppCore.shared
        let unseen = dwell.level != nil || core.palette.isVisible || core.isShowingDialog || core.island.resting == nil
        if notices.paused != unseen { notices.pause(unseen, at: time) }
        core.island.resting?.notice = notices.notice
        if let text = notices.announcement() {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            #if DEBUG
            IslandVerification.announcements.append(text)
            #endif
        }
        updateExpansion()
        noticeTask?.cancel()
        noticeTask = notices.remaining(at: time).map(expireWhenDwelled)
    }

    private func expireWhenDwelled(_ left: TimeInterval) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            try? await sleep(left)
            guard !Task.isCancelled, let self else { return }
            let gone = self.notices.notice?.id
            self.notices.expire(at: now())
            if let gone, self.notices.notice?.id != gone { self.noticeTaps[gone] = nil }
            self.noticesChanged()
        }
    }

    /// Sleeps out the dwell, then again for whatever repeats added, so a burst never restarts it.
    private func endWhenDwelled(_ token: Int) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            while let left = self?.dwell.remaining(token, at: now()) {
                try? await sleep(left)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.dwell.presentation == token, self.dwell.level == nil else { return }
            self.place()
            self.dwellTask = nil
            self.noticesChanged()
        }
    }

    private func settleWhenExpanded(_ token: Int) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            while let left = self?.expansion.remaining(token, at: now()) {
                try? await sleep(left)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.expansion.presentation == token else { return }
            self.expansionTask = nil
            self.updateExpansion()
        }
    }

    private func updateExpansion() {
        let core = AppCore.shared
        if expansion.update(carded: occurrence, waiting: dwell.level != nil || notices.notice != nil,
                            covered: core.palette.isVisible || core.isShowingDialog, at: now()) {
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
                guard self.dwell.level != nil || self.occurrence != nil || self.notices.notice != nil else { return }
                self.observePlacement()
                self.place()
                self.noticesChanged()
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
        noticeTask?.cancel()
    }
}
