import Foundation

/// Reads the two feed files and keeps the island's Agents page, badge and ask line current (#976).
@MainActor
final class AgentsModule: NotchcastModule {
    private let context: NotchcastContext
    private let system: AgentsSystem
    private var asks = AgentsAskLog()
    private var board: AgentsBoard?
    private var stopWatching: AgentsSystem.Cancel?
    private var cancelWake: AgentsSystem.Cancel?

    init(context: NotchcastContext, system: AgentsSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        system.prepare()
        stopWatching = system.watch { [weak self] in self?.reload() }
        reload()
    }

    func stop() {
        stopWatching?()
        stopWatching = nil
        cancelWake?()
        cancelWake = nil
        board = nil
        asks = AgentsAskLog()
        context.presenter.setPage(nil, id: AgentsBoard.id, onAction: nil)
        context.presenter.setStatus(nil, for: AgentsBoard.id, onTap: nil)
        context.presenter.end(notice: AgentsBoard.noticeID)
    }

    /// Runs on a folder event, on Command-R and when a feed goes stale; unchanged values post nothing.
    private func reload() {
        let now = context.now()
        let next = AgentsBoard(agents: AgentsFeed.read(system.read(AgentsFeed.fileName), now: now),
                               usage: UsageFeed.read(system.read(UsageFeed.fileName), now: now),
                               now: now, region: system.region())
        let last = board
        board = next
        if next.page != last?.page {
            context.presenter.setPage(next.page, id: AgentsBoard.id) { [weak self] in self?.act($0) }
        }
        if next.status != last?.status { context.presenter.setStatus(next.status, for: AgentsBoard.id, onTap: nil) }
        if next.agents.live != nil, let notice = AgentsBoard.notice(for: asks.fresh(in: next.waiting)) {
            context.presenter.post(notice, onTap: nil)
        }
        cancelWake?()
        cancelWake = next.nextRefresh.map { system.wake($0) { [weak self] in self?.reload() } }
    }

    private func act(_ action: String) {
        if action == IslandPage.refreshAction { return reload() }
        if let url = board?.url(for: action) { system.open(url) }
    }
}
