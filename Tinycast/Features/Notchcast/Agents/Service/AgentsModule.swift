import Foundation

/// Reads this Mac's accounts when due, merges the feed and posts the Agents page (#1128).
@MainActor
final class AgentsModule: NotchcastModule {
    let context: NotchcastContext
    private let system: AgentsSystem
    private var readings: [String: AgentAccount] = [:]
    private var attempts: [String: Attempt] = [:]
    private var feed: AgentFeedRead = .missing
    private var shows = false
    private var forced = false
    /// Set by whatever cuts the wait short, so a cut during a cycle still skips the next wait.
    private var woken = false
    private var loop: Task<Void, Never>?
    private var nap: Task<Void, Never>?

    /// The last check per account: when, and how many failed in a row with which state.
    struct Attempt: Equatable {
        var at: Date
        var failure: AgentAccountState?
        var repeated = 0
    }

    init(context: NotchcastContext, system: AgentsSystem) {
        self.context = context
        self.system = system
    }

    private var preferences: AgentsPreferences { AgentsPreferences(defaults: context.defaults) }
    var machineName: String { preferences.machineName ?? system.computerName() }

    func start() {
        context.presenter.watchPages(id: AgentPage.id) { [weak self] in self?.visible($0) }
        post()
        loop = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.cycle()
                await self.wait()
            }
        }
    }

    func stop() {
        loop?.cancel()
        nap?.cancel()
        loop = nil
        context.presenter.watchPages(id: AgentPage.id, onChange: nil)
        context.presenter.setPage(nil, id: AgentPage.id, onAction: nil)
    }

    /// The launcher command and its hotkey.
    func open() { context.presenter.showPage(id: AgentPage.id) }

    /// Command-R: every account is read again now, whatever its wait.
    func refresh() {
        forced = true
        wake()
    }

    private func wake() {
        woken = true
        nap?.cancel()
    }

    /// Settings changed a name, an account or the feed folder: show it at once and read what is new.
    func settingsChanged() {
        let names = Set(preferences.sources(home: system.home).map(\.name))
        readings = readings.filter { names.contains($0.key) }
        attempts = attempts.filter { names.contains($0.key) }
        post()
        wake()
    }

    private func visible(_ visible: Bool) {
        shows = visible
        if visible {
            post()
            wake()
        }
    }

    /// One minute, or less when Command-R, Settings or the page coming on show cuts it short.
    private func wait() async {
        guard !Task.isCancelled else { return }
        guard !woken else { return woken = false }
        let sleep = system.sleep
        let nap = Task { _ = try? await sleep(.seconds(AgentPollPolicy.shown)) }
        self.nap = nap
        await nap.value
        woken = false
    }

    /// Reads the due accounts one at a time, then the feed, then posts; a stop cancels the read under way.
    func cycle() async {
        let force = forced
        forced = false
        var read = false
        for source in preferences.sources(home: system.home) {
            let attempt = attempts[source.name]
            guard force || AgentPollPolicy.isDue(
                lastAttempt: attempt?.at, now: system.now(), failure: attempt?.failure,
                repeated: attempt?.repeated ?? 0, pageShows: shows) else { continue }
            let started = system.now()
            guard let account = try? await system.read(source), !Task.isCancelled else { return }
            // Settings may have removed or renamed the account while it was read.
            guard preferences.sources(home: system.home).contains(source) else { continue }
            record(account, previous: attempt, at: started)
            read = true
        }
        let folder = preferences.folder(default: system.defaultFeedFolder)
        if read {
            let local = AgentFeed(generatedAt: system.now(),
                                  machines: [AgentMachine(name: machineName, accounts: locals.compactMap(\.reading))])
            await system.writeLocal(folder, local)
        }
        feed = await system.readFeed(folder)
        guard !Task.isCancelled else { return }
        if read || shows { post() }
    }

    /// A failed read keeps the last numbers, marked so the card says it could not refresh.
    private func record(_ account: AgentAccount, previous: Attempt?, at started: Date) {
        let failure = account.state == .ok ? nil : account.state
        let before = previous.flatMap { $0.failure == .unavailable ? $0.repeated : nil } ?? 0
        let repeated = failure == .unavailable ? before + 1 : 0
        attempts[account.name] = Attempt(at: started, failure: failure, repeated: repeated)
        if account.state == .unavailable, var last = readings[account.name], !last.windows.isEmpty {
            last.state = .unavailable
            readings[account.name] = last
        } else {
            readings[account.name] = account
        }
    }

    /// Codex not installed is no card: it is only looked for, never asked for.
    private var locals: [AgentLocalAccount] {
        preferences.sources(home: system.home).compactMap { source in
            let reading = readings[source.name]
            if source == .codex, reading?.state == .missing { return nil }
            return AgentLocalAccount(name: source.name, provider: source.provider, reading: reading)
        }
    }

    func post() {
        let board = AgentBoard(machineName: machineName, local: locals, feed: feed, now: system.now())
        context.presenter.setPage(AgentPage.page(board), id: AgentPage.id) { [weak self] action in
            if action == IslandPage.refreshAction { self?.refresh() }
        }
    }
}
