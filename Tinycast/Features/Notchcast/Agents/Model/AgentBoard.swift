import Foundation

struct AgentMeter: Equatable, Sendable {
    var label: String
    var value: String
    var trailing: String?
    var fraction: Double
    var tick: Double?
    var thick: Bool
    var warning: Bool
    var note: String?
}

struct AgentCard: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        case meters([AgentMeter])
        case notice(glyph: String?, headline: String)
    }

    var title: String
    var tag: String
    /// A hollow card takes half a slot: a spent account or one that cannot be read.
    var hollow: Bool
    var body: Body
    var dimmed: Bool
    var caption: String?
    /// Under a notice's headline: which limit spent the account.
    var detail: String? = nil
    /// A reset the account holds in hand, as a chip beside its name.
    var credit: String? = nil
    /// The card as VoiceOver reads it, in words rather than the screen's short units.
    var spoken: String? = nil
}

struct AgentColumn: Equatable, Sendable {
    var title: String
    var cards: [AgentCard]
}

/// One of this Mac's accounts as Settings lists it, with its latest reading once there is one.
struct AgentLocalAccount: Equatable, Sendable {
    var name: String
    var provider: String
    var reading: AgentAccount?
}

enum AgentFeedRead: Equatable, Sendable {
    /// The normal case until something writes the feed: this Mac only, no error.
    case missing
    case unreadable
    case unknownVersion(Int)
    case loaded(AgentFeed)
}

struct AgentBoard: Equatable, Sendable {
    static let staleAfter: TimeInterval = 10 * 60

    var columns: [AgentColumn]
    var other: [AgentCard]
    /// The warned limit soonest to run out, else the fullest weekly.
    var homeLine: String?
    /// Why the other Macs are absent.
    var footnote: String?

    var isEmpty: Bool { columns.isEmpty && other.isEmpty }

    init(machineName: String, local: [AgentLocalAccount], feed: AgentFeedRead, now: Date) {
        let loaded: AgentFeed? = if case .loaded(let feed) = feed { feed } else { nil }
        var machines = (loaded?.machines ?? []).map { machine in
            (name: machine.name, accounts: machine.accounts.map {
                AgentLocalAccount(name: $0.name, provider: $0.provider, reading: $0)
            })
        }
        if let index = machines.firstIndex(where: { $0.name == machineName }) {
            machines[index].accounts = Self.merge(local: local, feed: machines[index].accounts.compactMap(\.reading))
        } else {
            machines.insert((machineName, local), at: 0)
        }
        var columns: [AgentColumn] = []
        var accounts: [AgentAccount] = []
        for machine in machines where !machine.accounts.isEmpty {
            let readings = machine.accounts.compactMap(\.reading)
            accounts += readings
            let spent = Set(readings.filter { $0.isSpent(now: now) }.map(\.name))
            let ordered = machine.accounts.filter { !spent.contains($0.name) }
                + machine.accounts.filter { spent.contains($0.name) }
            columns.append(AgentColumn(title: machine.name, cards: ordered.map { account in
                account.reading.map { Self.card($0, now: now) } ?? Self.reading(account)
            }))
        }
        self.columns = columns
        let shared = loaded?.shared ?? []
        other = shared.map { Self.card($0, now: now) }
        homeLine = Self.homeLine(accounts + shared, now: now)
        footnote = Self.footnote(feed)
    }

    /// The fresher of this Mac's own reading and the feed's copy wins, matched by name.
    private static func merge(local: [AgentLocalAccount], feed: [AgentAccount]) -> [AgentLocalAccount] {
        var merged = local.map { account in
            guard let copy = feed.first(where: { $0.name == account.name }) else { return account }
            var account = account
            if account.reading.map({ $0.checkedAt < copy.checkedAt }) ?? true { account.reading = copy }
            return account
        }
        for account in feed where !local.contains(where: { $0.name == account.name }) {
            merged.append(AgentLocalAccount(name: account.name, provider: account.provider, reading: account))
        }
        return merged
    }

    static func tag(_ provider: String) -> String {
        ["claude": "Claude", "codex": "Codex", "grok": "Grok", "opencode": "OpenCode",
         "antigravity": "Antigravity"][provider] ?? provider.capitalized
    }

    private static func tool(_ provider: String) -> String {
        provider == "claude" ? "Claude Code" : tag(provider)
    }

    private static func reading(_ account: AgentLocalAccount) -> AgentCard {
        AgentCard(
            title: account.name, tag: tag(account.provider), hollow: false,
            body: .notice(glyph: nil, headline: String(localized: "Reading…", table: "NotchcastAgents")),
            dimmed: false, caption: nil)
    }

    static func card(_ account: AgentAccount, now: Date) -> AgentCard {
        let tag = tag(account.provider)
        let tool = tool(account.provider)
        let notice: (String, String)? =
            switch account.state {
            case .signedOut:
                ("person.crop.circle.badge.exclamationmark",
                 String(localized: "Sign in to \(tool)", table: "NotchcastAgents"))
            case .missing:
                ("questionmark.app.dashed", String(localized: "\(tool) not found", table: "NotchcastAgents"))
            case .outdated:
                ("arrow.down.app", String(localized: "Update \(tool)", table: "NotchcastAgents"))
            case .unavailable where account.windows.isEmpty:
                ("exclamationmark.triangle", String(localized: "Couldn’t read usage", table: "NotchcastAgents"))
            case .ok, .unavailable: nil
            }
        if let (glyph, headline) = notice {
            return AgentCard(
                title: account.name, tag: tag, hollow: true, body: .notice(glyph: glyph, headline: headline),
                dimmed: false, caption: nil, spoken: "\(account.name). \(headline)")
        }
        let credit = credits(account.resetCredits)
        if account.isSpent(now: now) {
            let back = account.backAt(now: now).map {
                String(localized: "Back in \(AgentDuration.text($0.timeIntervalSince(now)))", table: "NotchcastAgents")
            }
            let headline = back ?? String(localized: "Spent", table: "NotchcastAgents")
            let detail = spentDetail(account, now: now)
            return AgentCard(
                title: account.name, tag: tag, hollow: true, body: .notice(glyph: "hourglass", headline: headline),
                dimmed: false, caption: nil, detail: detail, credit: credit,
                spoken: [account.name, credit, headline, detail].compactMap(\.self).joined(separator: ". "))
        }
        let age = AgentDuration.text(now.timeIntervalSince(account.checkedAt))
        let failed = account.state == .unavailable
        let stale = failed || now.timeIntervalSince(account.checkedAt) > staleAfter
        let caption: String? =
            if failed {
                String(localized: "Couldn’t refresh · updated \(age) ago", table: "NotchcastAgents")
            } else if stale {
                String(localized: "Updated \(age) ago", table: "NotchcastAgents")
            } else {
                nil
            }
        let windows = account.currentWindows(now: now).sorted { lhs, rhs in
            lhs.kind != rhs.kind ? lhs.kind < rhs.kind : lhs.scope == nil && rhs.scope != nil
        }
        let extra = account.extraUsage.flatMap(extraMeter)
        let spokenWindows = windows.map { spoken($0, now: now) } + [extra.map { "\($0.label), \($0.value), \($0.trailing ?? "")" }]
        return AgentCard(
            title: account.name, tag: tag, hollow: false,
            body: .meters(windows.map { meter($0, now: now) } + [extra].compactMap(\.self)),
            dimmed: stale, caption: caption, credit: credit,
            spoken: ([account.name, credit] + spokenWindows + [caption]).compactMap(\.self).joined(separator: ". "))
    }

    /// "1 reset credit", "2 Fable reset credits"; none in hand draws nothing.
    static func credits(_ credits: AgentResetCredits?) -> String? {
        guard let credits, credits.count > 0 else { return nil }
        let count = credits.count
        return switch (credits.scope, count == 1) {
        case (let scope?, true): String(localized: "1 \(scope) reset credit", table: "NotchcastAgents")
        case (let scope?, false): String(localized: "\(count) \(scope) reset credits", table: "NotchcastAgents")
        case (nil, true): String(localized: "1 reset credit", table: "NotchcastAgents")
        case (nil, false): String(localized: "\(count) reset credits", table: "NotchcastAgents")
        }
    }

    /// Extra usage only with a limit to measure it against: "$34 of $200".
    private static func extraMeter(_ extra: AgentExtraUsage) -> AgentMeter? {
        guard let limit = extra.limit, limit > 0, extra.used.isFinite else { return nil }
        let money = Decimal.FormatStyle.Currency(code: extra.currency, locale: Locale(identifier: "en_US"))
            .precision(.fractionLength(0))
        let used = Decimal(extra.used).formatted(money)
        let of = Decimal(limit).formatted(money)
        return AgentMeter(
            label: String(localized: "Extra usage", table: "NotchcastAgents"), value: percent(extra.used / limit * 100),
            trailing: String(localized: "\(used) of \(of)", table: "NotchcastAgents"), fraction: min(extra.used / limit, 1),
            tick: nil, thick: false, warning: false, note: nil)
    }

    /// Which limit spent it: the one that renews last, as "Back in" counts to it.
    private static func spentDetail(_ account: AgentAccount, now: Date) -> String {
        let last = account.spentWindows(now: now).max { ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast) }
        return switch last?.kind {
        case .session?: String(localized: "Session limit used up", table: "NotchcastAgents")
        case .weekly?: String(localized: "Weekly limit used up", table: "NotchcastAgents")
        case .monthly?: String(localized: "Monthly limit used up", table: "NotchcastAgents")
        case .other?, nil: String(localized: "Limit used up", table: "NotchcastAgents")
        }
    }

    /// "Weekly, 45 percent used, resets in 5 days 14 hours".
    private static func spoken(_ window: AgentWindow, now: Date) -> String {
        let percent = Int(window.usedPercent.rounded(.down))
        let used = String(localized: "\(percent) percent used", table: "NotchcastAgents")
        guard let resets = window.resetsAt else { return "\(label(window)), \(used)" }
        let left = AgentDuration.spoken(resets.timeIntervalSince(now))
        return "\(label(window)), \(used), " + String(localized: "resets in \(left)", table: "NotchcastAgents")
    }

    static func label(_ window: AgentWindow) -> String {
        if let label = window.label { return label }
        let kind: String? =
            switch window.kind {
            case .session: String(localized: "Session", table: "NotchcastAgents")
            case .weekly: String(localized: "Weekly", table: "NotchcastAgents")
            case .monthly: String(localized: "Monthly", table: "NotchcastAgents")
            case .other: nil
            }
        switch (kind, window.scope) {
        case (let kind?, let scope?): return "\(kind) · \(scope)"
        case (let kind?, nil): return kind
        case (nil, let scope?): return scope
        case (nil, nil): return String(localized: "Limit", table: "NotchcastAgents")
        }
    }

    static func percent(_ used: Double) -> String { "\(Int(used.rounded(.down)))%" }

    private static func meter(_ window: AgentWindow, now: Date) -> AgentMeter {
        let pace = AgentPace(window, now: now)
        return AgentMeter(
            label: label(window), value: percent(window.usedPercent),
            trailing: window.resetsAt.map { AgentDuration.until($0, now: now) },
            fraction: window.usedPercent / 100, tick: pace?.tick, thick: window.kind == .weekly && window.scope == nil,
            warning: pace?.warns ?? false,
            note: pace?.runsOutIn.map {
                String(localized: "Runs out in \(AgentDuration.text($0))", table: "NotchcastAgents")
            })
    }

    private static func homeLine(_ accounts: [AgentAccount], now: Date) -> String? {
        let live = accounts.filter { $0.state == .ok && !$0.isSpent(now: now) }
        let windows = live.flatMap { account in account.currentWindows(now: now).map { (account.name, $0) } }
        let warned = windows.compactMap { name, window in
            AgentPace(window, now: now)?.runsOutIn.map { (name, window, $0) }
        }
        if let (name, window, left) = warned.min(by: { $0.2 < $1.2 }) {
            let runsOut = String(localized: "runs out in \(AgentDuration.text(left))", table: "NotchcastAgents")
            return "\(name) · \(label(window)) \(runsOut)"
        }
        guard let (name, window) = windows.filter({ $0.1.kind == .weekly }).max(by: { $0.1.usedPercent < $1.1.usedPercent })
        else { return nil }
        return "\(name) · \(label(window)) \(percent(window.usedPercent))"
    }

    private static func footnote(_ feed: AgentFeedRead) -> String? {
        switch feed {
        case .loaded: nil
        case .missing: String(localized: "This Mac only: no feed found.", table: "NotchcastAgents")
        case .unreadable: String(localized: "This Mac only: the feed couldn’t be read.", table: "NotchcastAgents")
        case .unknownVersion(let version):
            String(localized: "This Mac only: feed version \(version) is newer than this app.", table: "NotchcastAgents")
        }
    }
}
