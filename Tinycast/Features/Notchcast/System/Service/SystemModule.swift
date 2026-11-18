import Foundation

/// Samples the Mac while the switch is on; posts the System page and, while hot, the closed island's status.
@MainActor
final class SystemModule: NotchcastModule {
    /// One read serves the page and the hot check (decision 946: every 15 s in the background).
    static let interval: Duration = .seconds(15)
    /// A rate needs two reads, so the second follows the first this soon.
    static let warmUp: Duration = .seconds(1)

    private let context: NotchcastContext
    private let probe: @Sendable () async -> SystemCounters?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let locale: Locale
    private var baseline: SystemCounters?
    private var hot = SystemHotState()
    private var status: IslandStatus?
    private var run = 0
    private var isSampling = false
    private(set) var loop: Task<Void, Never>?
    private(set) var refresh: Task<Void, Never>?

    init(context: NotchcastContext, probe: @escaping @Sendable () async -> SystemCounters? = SystemProbe.sample,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         locale: Locale = .current) {
        self.context = context
        self.probe = probe
        self.sleep = sleep
        self.locale = locale
    }

    func start() {
        guard loop == nil else { return }
        let sleep = sleep
        loop = Task { [weak self] in
            var pause = Self.warmUp
            while !Task.isCancelled {
                await self?.sample()
                if self == nil { return }
                do { try await sleep(pause) } catch { return }
                pause = Self.interval
            }
        }
    }

    func stop() {
        guard loop != nil else { return }
        loop?.cancel()
        loop = nil
        refresh?.cancel()
        refresh = nil
        run += 1
        isSampling = false
        baseline = nil
        hot = SystemHotState()
        status = nil
        context.presenter.setPage(nil, id: SystemPage.id, onAction: nil)
        context.presenter.setStatus(nil, for: SystemPage.statusID, onTap: nil)
    }

    /// One read at a time; a read that returns after `stop` belongs to no run and is dropped.
    func sample() async {
        guard loop != nil, !isSampling else { return }
        isSampling = true
        let run = run
        let counters = await probe()
        guard run == self.run else { return }
        isSampling = false
        guard let counters else { return }
        guard let previous = baseline, let reading = SystemReading(previous: previous, current: counters) else {
            let elapsed = baseline.map { counters.at - $0.at }
            // A read right after the last one (Command-R) keeps the older baseline, so the next rate is real.
            if elapsed.map({ (0..<SystemReading.minimumGap).contains($0) }) != true {
                baseline = counters
                hot.pause()
            }
            return
        }
        baseline = counters
        hot.update(reading)
        post(reading)
    }

    private func post(_ reading: SystemReading) {
        let page = SystemPage.page(reading, warnings: hot.warnings, locale: locale)
        context.presenter.setPage(page, id: SystemPage.id) { [weak self] action in
            guard action == IslandPage.refreshAction, let self else { return }
            self.refresh = Task { [weak self] in await self?.sample() }
        }
        // Setting a status makes it the island's newest, so only a change is sent.
        let status = SystemPage.status(hot.warnings)
        guard status != self.status else { return }
        self.status = status
        context.presenter.setStatus(status, for: SystemPage.statusID, onTap: nil)
    }
}
