import AppKit

/// Ticks the nearest timer in the pill, rings each at zero until dismissed, lists all in the pill menu.
@MainActor
final class TimersModule: NotchcastModule {
    struct Environment {
        var calendar: () -> Calendar
        var sleep: @MainActor (TimeInterval) async throws -> Void
        var chime: @MainActor () -> Void

        static var live: Environment {
            Environment(
                calendar: { .autoupdatingCurrent },
                sleep: { try await Task.sleep(for: .seconds($0)) },
                chime: { _ = NSSound(named: "Glass")?.play() })
        }
    }

    static let statusID = "timers"
    static let menuOwner = "timers"
    /// A ring stays until it is dismissed; a day stands in for forever, which `Task.sleep` cannot take.
    static let ringSeconds: TimeInterval = 24 * 3600
    /// A wall-clock change (travel, a manual set) is picked up within this, even far from zero.
    static let longestWait: TimeInterval = 60

    private let context: NotchcastContext
    private let environment: Environment
    private let store: TimerStore
    private var timers: [TimerEntry] = []
    private var ringing: [TimerEntry] = []
    private var menuRows: [IslandMenuRow] = []
    private var tick: Task<Void, Never>?
    private var isRunning = false

    init(context: NotchcastContext, environment: Environment = .live) {
        self.context = context
        self.environment = environment
        store = TimerStore(defaults: context.defaults)
    }

    private var presenter: any IslandPresenting { context.presenter }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let (running, missed) = store.resume(at: context.now())
        timers = running
        for timer in missed { ring(timer, missed: true) }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        tick?.cancel()
        tick = nil
        for timer in ringing { presenter.end(notice: Self.noticeID(timer)) }
        ringing = []
        timers = []
        menuRows = []
        presenter.setStatus(nil, for: Self.statusID, onTap: nil)
        presenter.setMenuRows([], owner: Self.menuOwner) { _ in }
    }

    func start(_ text: String) {
        guard isRunning else { return }
        switch TimerInput.parse(text, now: context.now(), calendar: environment.calendar()) {
        case .failure(let error):
            let message = switch error {
            case .unreadable: String(localized: "Use 25, 1h30m, 90s or 07:30", table: "NotchcastTimers")
            case .tooLong: String(localized: "Timers run up to 99 hours", table: "NotchcastTimers")
            }
            presenter.post(IslandNotice(id: "timers.input", symbol: "timer", text: message, isFailure: true),
                           onTap: nil)
        case .success(let request):
            let timer = TimerEntry(id: UUID(), end: request.end, label: request.label, isAlarm: request.isAlarm)
            timers.append(timer)
            store.save(timers)
            presenter.post(IslandNotice(id: "timers.started", symbol: TimersText.symbol(timer),
                                        text: TimersText.started(timer, now: context.now())), onTap: nil)
            refresh()
        }
    }

    /// Stop Timer: every running timer goes, and every ring with it.
    func stopAll() {
        guard isRunning else { return }
        let count = timers.count + ringing.count
        timers = []
        store.save([])
        for timer in ringing { presenter.end(notice: Self.noticeID(timer)) }
        ringing = []
        presenter.post(IslandNotice(id: "timers.stopped", symbol: "stop.circle", text: TimersText.stopped(count)),
                       onTap: nil)
        refresh()
    }

    /// One pass: ring what has ended, show the nearest, sleep until its text changes.
    func refresh() {
        tick?.cancel()
        tick = nil
        guard isRunning else { return }
        let now = context.now()
        let (running, ended) = TimerEntry.split(timers, at: now)
        timers = running
        if !ended.isEmpty {
            store.save(timers)
            for timer in ended { ring(timer, missed: false) }
        }
        updateMenu()
        guard let nearest = timers.first else {
            return presenter.setStatus(nil, for: Self.statusID, onTap: nil)
        }
        let remaining = nearest.end.timeIntervalSince(now)
        let status = IslandStatus(
            id: Self.statusID, symbol: TimersText.symbol(nearest), text: TimerClock.text(remaining: remaining),
            label: TimersText.spoken(nearest, remaining: remaining))
        presenter.setStatus(status, for: Self.statusID, onTap: nil)
        let wait = min(TimerClock.untilChange(remaining: remaining), Self.longestWait)
        tick = Task { [weak self, sleep = environment.sleep] in
            do { try await sleep(wait) } catch { return }
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.tick = nil
            self.refresh()
        }
    }

    private func ring(_ timer: TimerEntry, missed: Bool) {
        ringing.append(timer)
        if !missed { environment.chime() }
        let notice = IslandNotice(
            id: Self.noticeID(timer), symbol: TimersText.symbol(timer),
            text: missed ? TimersText.missed(timer) : TimersText.ringing(timer), seconds: Self.ringSeconds)
        presenter.post(notice, onTap: { [weak self] in self?.remove(timer.id) })
    }

    /// A menu row or a tap on a ring: a running timer stops, a ring is dismissed.
    private func remove(_ id: UUID) {
        guard isRunning else { return }
        if let index = ringing.firstIndex(where: { $0.id == id }) {
            presenter.end(notice: Self.noticeID(ringing.remove(at: index)))
        } else if let index = timers.firstIndex(where: { $0.id == id }) {
            timers.remove(at: index)
            store.save(timers)
        }
        refresh()
    }

    private func updateMenu() {
        let rows = ringing.map { IslandMenuRow(id: $0.id.uuidString, title: TimersText.dismissRow($0)) }
            + timers.map { IslandMenuRow(id: $0.id.uuidString, title: TimersText.stopRow($0)) }
        guard rows != menuRows else { return }
        menuRows = rows
        presenter.setMenuRows(rows, owner: Self.menuOwner) { [weak self] id in
            if let id = UUID(uuidString: id) { self?.remove(id) }
        }
    }

    static func noticeID(_ timer: TimerEntry) -> String { "timers.ring." + timer.id.uuidString }
}
