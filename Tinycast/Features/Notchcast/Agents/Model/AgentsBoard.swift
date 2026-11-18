import Foundation

/// Everything the Agents add-on shows, worked out from the two readings at one instant (#976).
struct AgentsBoard: Equatable, Sendable {
    typealias Agent = AgentsFeed.Agent

    static let id = "agents"
    static let noticeID = "agents.ask"
    static let openPrefix = "open:"
    static let maxRows = 8
    static let defaultWarnBelow = 20.0

    var agents: AgentsReading<AgentsFeed>
    var usage: AgentsReading<UsageFeed>
    var now: Date
    var region: AgentsRegion

    /// Only a live feed has anyone waiting: a stale ask may be long answered.
    var waiting: [Agent] { agents.live?.agents.filter(\.needsInput) ?? [] }

    var working: Int { agents.live?.agents.filter { !$0.needsInput && $0.status == .working }.count ?? 0 }

    /// The plan closest to running out, from a live feed only.
    var lowest: UsageFeed.Meter? { usage.live?.meters.min { $0.percentLeft < $1.percentLeft } }

    private var lowPlan: UsageFeed.Meter? {
        usage.live?.meters.filter { $0.percentLeft < $0.warnBelow ?? Self.defaultWarnBelow }
            .min { $0.percentLeft < $1.percentLeft }
    }

    /// The closed island's badge: who waits, else a plan nearly used up, ranked as 946-3 orders them.
    var status: IslandStatus? {
        let count = waiting.count
        if count > 0 {
            return IslandStatus(id: Self.id, symbol: "questionmark.bubble", text: count > 99 ? "99+" : "\(count)",
                                label: Self.waitingText(count), rank: .agentWaiting)
        }
        return lowPlan.map {
            IslandStatus(id: Self.id, symbol: "gauge.with.dots.needle.33percent",
                         text: AgentsFormat.percent($0.percentLeft, locale: region.locale), label: planText($0),
                         rank: .lowPlan)
        }
    }

    /// Nil while neither file exists, so the module leaves no tab (design §17).
    var page: IslandPage? {
        if agents == .missing, usage == .missing { return nil }
        return IslandPage(id: Self.id, title: String(localized: "Agents", table: "NotchcastAgents"), symbol: "person.2",
                          order: 0, badge: waiting.count, line: line, blocks: agentBlocks + usageBlocks)
    }

    /// Seconds until the page reads differently: a feed going stale, else the minute its times turn.
    var nextRefresh: TimeInterval? {
        guard page != nil else { return nil }
        let deadlines = [agents.live.map { $0.updatedAt.addingTimeInterval($0.staleAfter) },
                         usage.live.map { $0.updatedAt.addingTimeInterval($0.staleAfter) }]
        return max(1, deadlines.compactMap { $0?.timeIntervalSince(now) }.reduce(60, min))
    }

    /// Where a row's button leads: the agent's own link, else the feed's.
    func url(for action: String) -> URL? {
        guard action.hasPrefix(Self.openPrefix), let feed = agents.feed else { return nil }
        let id = action.dropFirst(Self.openPrefix.count)
        return feed.agents.first { $0.id == id }.flatMap { $0.openURL ?? feed.openURL }
    }

    /// One line for the asks that just arrived; the badge then stays until they are answered.
    static func notice(for fresh: [Agent]) -> IslandNotice? {
        guard let first = fresh.first else { return nil }
        let text = fresh.count == 1
            ? String(localized: "Agent needs you: \(first.title)", table: "NotchcastAgents")
            : String(localized: "\(fresh.count) agents need you", table: "NotchcastAgents")
        return IslandNotice(id: noticeID, symbol: "questionmark.bubble", text: text)
    }

    private var line: IslandPageLine {
        let plan = lowest.map(planText)
        let count = waiting.count
        if count > 0 { return IslandPageLine(symbol: "person.2", text: Self.waitingText(count), detail: plan) }
        let busy = working > 0 ? Self.workingText(working) : nil
        if let plan { return IslandPageLine(symbol: "person.2", text: plan, detail: busy) }
        if let busy { return IslandPageLine(symbol: "person.2", text: busy) }
        let isStale = agents.feed != nil && agents.live == nil || usage.feed != nil && usage.live == nil
        let text = if isStale {
            String(localized: "Stale", table: "NotchcastAgents")
        } else if agents.live != nil {
            String(localized: "No agents working", table: "NotchcastAgents")
        } else {
            String(localized: "No data", table: "NotchcastAgents")
        }
        return IslandPageLine(symbol: "person.2", text: text)
    }

    private var agentBlocks: [IslandPageBlock] {
        switch agents {
        case .missing: return []
        case .unreadable: return [Self.unreadable(AgentsFeed.fileName)]
        case .stale(let feed):
            let moment = AgentsFormat.moment(feed.updatedAt, now: now, region: region)
            return [Self.stale(String(localized: "Agents updated \(moment)", table: "NotchcastAgents"))] + rows(feed)
        case .live(let feed):
            let listed = rows(feed)
            let quiet = IslandPageRow(symbol: "person.2", title: String(localized: "No agents working",
                                                                         table: "NotchcastAgents"))
            return listed.isEmpty ? [.row(quiet)] : listed
        }
    }

    private var usageBlocks: [IslandPageBlock] {
        switch usage {
        case .missing: return []
        case .unreadable: return [Self.unreadable(UsageFeed.fileName)]
        case .stale(let feed):
            let moment = AgentsFormat.moment(feed.updatedAt, now: now, region: region)
            return [Self.stale(String(localized: "AI plan updated \(moment)", table: "NotchcastAgents"))]
                + feed.meters.map(meter)
        case .live(let feed): return feed.meters.map(meter)
        }
    }

    /// Asking agents first, then each coordinator above its workers, in the feed's order.
    private func rows(_ feed: AgentsFeed) -> [IslandPageBlock] {
        let asking = waiting
        let askingIDs = Set(asking.map(\.id))
        let byID = Dictionary(feed.agents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func lead(_ agent: Agent) -> String {
            var id = agent.id
            for _ in 0..<8 {
                guard let parent = byID[id]?.parent, byID[parent] != nil else { break }
                id = parent
            }
            return id
        }
        let listed = feed.agents.filter { !askingIDs.contains($0.id) && $0.status != .done && $0.status != .idle }
        let teams = Dictionary(grouping: listed, by: lead)
        var rows = asking.map { agent in
            row(agent, feed: feed, symbol: "questionmark.bubble",
                detail: agent.ask ?? agent.statusText ?? String(localized: "Waiting for you", table: "NotchcastAgents"),
                trailing: String(localized: "Open", table: "NotchcastAgents"))
        }
        var placed = Set<String>()
        for agent in feed.agents {
            let head = lead(agent)
            guard let team = teams[head], placed.insert(head).inserted else { continue }
            let heads = askingIDs.contains(head) ? [] : [byID[head]].compactMap { $0 }
            rows += heads.map { row($0, feed: feed, symbol: $0.role == .coordinator ? "person.2" : "person") }
            rows += team.filter { $0.id != head }.map {
                row($0, feed: feed, symbol: heads.isEmpty ? "person" : "arrow.turn.down.right")
            }
        }
        guard rows.count > Self.maxRows else { return rows }
        let more = IslandPageRow(symbol: "ellipsis", title: String(
            localized: "\(rows.count - Self.maxRows + 1) more", table: "NotchcastAgents"))
        return Array(rows.prefix(Self.maxRows - 1)) + [.row(more)]
    }

    private func row(_ agent: Agent, feed: AgentsFeed, symbol: String) -> IslandPageBlock {
        let detail = [agent.group, agent.statusText].compactMap { $0 }.joined(separator: " · ")
        let elapsed = agent.since.map { AgentsFormat.duration(now.timeIntervalSince($0), region: region) }
        return row(agent, feed: feed, symbol: agent.status == .failed ? "exclamationmark.triangle" : symbol,
                   detail: detail.isEmpty ? nil : detail, trailing: elapsed)
    }

    /// A row with somewhere to go is a button; one without stays plain text.
    private func row(_ agent: Agent, feed: AgentsFeed, symbol: String, detail: String?,
                     trailing: String?) -> IslandPageBlock {
        let opens = (agent.openURL ?? feed.openURL) != nil
        return .row(IslandPageRow(id: opens ? Self.openPrefix + agent.id : nil, symbol: symbol, title: agent.title,
                                  detail: detail, trailing: opens || !agent.needsInput ? trailing : nil))
    }

    private func meter(_ meter: UsageFeed.Meter) -> IslandPageBlock {
        let share = AgentsFormat.percent(meter.percentLeft, locale: region.locale)
        let countdown = meter.resetsAt.flatMap {
            $0 > now ? AgentsFormat.duration($0.timeIntervalSince(now), region: region) : nil
        }
        let value = if let countdown {
            String(localized: "\(share) left · resets in \(countdown)", table: "NotchcastAgents")
        } else {
            String(localized: "\(share) left", table: "NotchcastAgents")
        }
        return .meter(IslandPageMeter(label: meter.label, fraction: meter.percentLeft / 100, value: value))
    }

    private func planText(_ meter: UsageFeed.Meter) -> String {
        String(localized: "AI plan \(AgentsFormat.percent(meter.percentLeft, locale: region.locale)) left",
               table: "NotchcastAgents")
    }

    private static func waitingText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 agent waiting", table: "NotchcastAgents")
            : String(localized: "\(count) agents waiting", table: "NotchcastAgents")
    }

    private static func workingText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 agent working", table: "NotchcastAgents")
            : String(localized: "\(count) agents working", table: "NotchcastAgents")
    }

    private static func unreadable(_ fileName: String) -> IslandPageBlock {
        .row(IslandPageRow(symbol: "questionmark.folder", title: String(localized: "No data", table: "NotchcastAgents"),
                           detail: String(localized: "\(fileName) could not be read", table: "NotchcastAgents")))
    }

    private static func stale(_ detail: String) -> IslandPageBlock {
        .row(IslandPageRow(symbol: "clock.badge.exclamationmark",
                           title: String(localized: "Stale", table: "NotchcastAgents"), detail: detail))
    }
}

/// Which asks already showed their line, so each request shows it once (#976 behaviour 4).
struct AgentsAskLog: Equatable, Sendable {
    private var shown: Set<String> = []

    /// The agents asking something new; an answered ask is forgotten, so asking again shows again.
    mutating func fresh(in waiting: [AgentsFeed.Agent]) -> [AgentsFeed.Agent] {
        let fresh = waiting.filter { !shown.contains(Self.key($0)) }
        shown = Set(waiting.map(Self.key))
        return fresh
    }

    private static func key(_ agent: AgentsFeed.Agent) -> String { agent.id + "\n" + (agent.ask ?? "") }
}
