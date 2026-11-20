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
    /// Read on another machine and passed on by the feed, so it arrives older.
    var remote = false
    /// A Claude config folder as Settings or the feed writes it; empty is `~/.claude`.
    var folder: String? = nil
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
    /// A feed reading is up to 10 min old when pushed, plus a 5 min push and T3's own delay.
    static let feedStaleAfter: TimeInterval = 25 * 60

    var columns: [AgentColumn]
    var other: [AgentCard]
    /// The warned limit soonest to run out, else the weekly with least left.
    var homeLine: String?
    /// Why the other Macs are absent.
    var footnote: String?

    var isEmpty: Bool { columns.isEmpty && other.isEmpty }

    /// Window meters per card, Extra usage aside, so no card outgrows the slot the board drew.
    static let meterCap = 3

    init(home: URL, machineName: String, local: [AgentLocalAccount], feed: AgentFeedRead, now: Date) {
        let loaded: AgentFeed? = if case .loaded(let feed) = feed { feed } else { nil }
        var machines = (loaded?.machines ?? []).map { machine in
            (name: machine.name, accounts: machine.accounts.map {
                AgentLocalAccount(name: $0.name, provider: $0.provider, reading: $0, remote: true, folder: $0.folder)
            })
        }
        let shared = loaded?.shared ?? []
        let copies = local.map { Self.copy(of: $0, local: local, shared: shared) }
        let own = zip(local, copies).filter { $1 == nil }.map(\.0)
        if let index = machines.firstIndex(where: { $0.name == machineName }) {
            machines[index].accounts = Self.merge(local: own, feed: machines[index].accounts, home: home, now: now)
        } else {
            machines.insert((machineName, own), at: 0)
        }
        var columns: [AgentColumn] = []
        var accounts: [AgentAccount] = []
        machines.removeAll { $0.accounts.isEmpty }
        // One Mac flows its cards over the grid, where moving a spent one last would move every card.
        let spentLast = machines.count > 1
        for machine in machines {
            let readings = machine.accounts.compactMap(\.reading)
            accounts += readings
            let spent = spentLast ? Set(readings.filter { $0.isSpent(now: now) }.map(\.name)) : []
            let ordered = machine.accounts.filter { !spent.contains($0.name) }
                + machine.accounts.filter { spent.contains($0.name) }
            columns.append(AgentColumn(title: machine.name, cards: ordered.map { Self.card($0, now: now) }))
        }
        self.columns = columns
        let others = shared.enumerated().map { index, account in
            let remote = AgentLocalAccount(name: account.name, provider: account.provider, reading: account, remote: true)
            return zip(local, copies).first { $1 == index }.map { Self.pick($0.0, remote, now: now) } ?? remote
        }
        other = others.map { Self.card($0, now: now) }
        homeLine = Self.homeLine(accounts + others.compactMap(\.reading), now: now)
        footnote = Self.footnote(feed)
    }

    /// This Mac and the gate may name one account differently, so one of a provider matches too.
    private static func copy(of account: AgentLocalAccount, local: [AgentLocalAccount], shared: [AgentAccount]) -> Int? {
        let same = shared.indices.filter { shared[$0].provider == account.provider }
        if let named = same.first(where: { shared[$0].name == account.name }) { return named }
        let alone = same.count == 1 && local.count(where: { $0.provider == account.provider }) == 1
        return alone ? same.first : nil
    }

    /// This Mac's accounts, each merged with the feed's copy, then the feed's own; a copy merges once.
    private static func merge(local: [AgentLocalAccount], feed: [AgentLocalAccount], home: URL, now: Date)
        -> [AgentLocalAccount]
    {
        var copies: [Int?] = []
        for account in local {
            copies.append(feed.indices.first { !copies.contains($0) && same(account, feed[$0], home: home) })
        }
        let merged = zip(local, copies).map { account, index -> AgentLocalAccount in
            guard let index else { return account }
            var merged = pick(account, feed[index], now: now)
            // Settings' own default name gives way to the gate's; a typed one stays.
            if let folder = account.folder, account.name != ClaudeLaunch.defaultName(directory: folder) {
                merged.name = account.name
                merged.reading?.name = account.name
            }
            return merged
        }
        return merged + feed.indices.filter { !copies.contains($0) }.map { feed[$0] }
    }

    /// One Claude config folder when the feed names it, else one name.
    private static func same(_ own: AgentLocalAccount, _ copy: AgentLocalAccount, home: URL) -> Bool {
        guard own.provider == copy.provider, let mine = own.folder, let theirs = copy.folder else {
            return own.name == copy.name
        }
        return ClaudeLaunch.path(mine, home: home) == ClaudeLaunch.path(theirs, home: home)
    }

    /// This Mac's reading wins unless failed beside a good copy, or stale beside a fresher one.
    private static func pick(_ own: AgentLocalAccount, _ copy: AgentLocalAccount, now: Date) -> AgentLocalAccount {
        guard let mine = own.reading, let theirs = copy.reading else { return own.reading == nil ? copy : own }
        let stale = now.timeIntervalSince(mine.checkedAt) > staleAfter
        let failed = mine.state != .ok && theirs.state == .ok
        var winner = failed || (stale && theirs.checkedAt > mine.checkedAt) ? copy : own
        var reading = winner.remote ? theirs : mine
        let loser = winner.remote ? own : copy
        reading.name = copy.name
        // A stale copy lends nothing, or a credit spent since would come back.
        if let lent = loser.reading,
           now.timeIntervalSince(lent.checkedAt) <= (loser.remote ? feedStaleAfter : staleAfter) {
            reading.resetCredits = reading.resetCredits ?? lent.resetCredits
            reading.extraUsage = reading.extraUsage ?? lent.extraUsage
        }
        winner.name = copy.name
        winner.reading = reading
        return winner
    }

    static func providerName(_ provider: String) -> String {
        ["claude": "Claude", "codex": "Codex", "grok": "Grok", "opencode": "OpenCode",
         "antigravity": "Antigravity"][provider] ?? provider.capitalized
    }

    private static func tool(_ provider: String) -> String {
        provider == "claude" ? "Claude Code" : providerName(provider)
    }

    private static func reading(_ account: AgentLocalAccount) -> AgentCard {
        AgentCard(
            title: account.name, hollow: false,
            body: .notice(glyph: nil, headline: String(localized: "Reading…", table: "NotchcastAgents")),
            dimmed: false, caption: nil)
    }

    private static func card(_ account: AgentLocalAccount, now: Date) -> AgentCard {
        account.reading.map { card($0, now: now, staleAfter: account.remote ? feedStaleAfter : staleAfter) }
            ?? reading(account)
    }

    static func card(_ account: AgentAccount, now: Date, staleAfter: TimeInterval = staleAfter) -> AgentCard {
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
                title: account.name, hollow: true, body: .notice(glyph: glyph, headline: headline),
                dimmed: false, caption: nil, spoken: "\(account.name). \(headline)")
        }
        let credit = credits(account.resetCredits, now: now)
        if account.isSpent(now: now) {
            let back = account.backAt(now: now).map {
                String(localized: "Back in \(AgentDuration.text($0.timeIntervalSince(now)))", table: "NotchcastAgents")
            }
            let headline = back ?? String(localized: "Spent", table: "NotchcastAgents")
            let detail = spentDetail(account, now: now)
            return AgentCard(
                title: account.name, hollow: true, body: .notice(glyph: "hourglass", headline: headline),
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
        let (shown, more) = capped(windows.map { meter($0, now: now) })
        let meters = shown + [extra].compactMap(\.self)
        return AgentCard(
            title: account.name, hollow: false,
            body: .meters(meters),
            dimmed: stale, caption: caption ?? more, credit: credit,
            spoken: ([account.name, credit] + spokenWindows + [caption]).compactMap(\.self).joined(separator: ". "))
    }

    /// Past the cap, warned meters and then the lowest stay in order; one line counts the rest.
    private static func capped(_ meters: [AgentMeter]) -> ([AgentMeter], String?) {
        guard meters.count > meterCap else { return (meters, nil) }
        let rank = { (index: Int) in (meters[index].warning ? 0 : 1, meters[index].fraction, index) }
        let kept = Set(meters.indices.sorted { rank($0) < rank($1) }.prefix(meterCap))
        let hidden = meters.indices.filter { !kept.contains($0) }.map { meters[$0] }
        let count = hidden.count
        let lowest = hidden.min { $0.fraction < $1.fraction }?.value ?? ""
        let line = count == 1 ? String(localized: "1 more, \(lowest)", table: "NotchcastAgents")
            : String(localized: "\(count) more, none under \(lowest)", table: "NotchcastAgents")
        return (meters.indices.filter(kept.contains).map { meters[$0] }, line)
    }

    /// "1 reset credit", "2 Fable reset credits"; none in hand, or lapsed, draws nothing.
    static func credits(_ credits: AgentResetCredits?, now: Date) -> String? {
        guard let credits, credits.count > 0, credits.expiresAt.map({ $0 > now }) ?? true else { return nil }
        let count = credits.count
        return switch (credits.scope, count == 1) {
        case (let scope?, true): String(localized: "1 \(scope) reset credit", table: "NotchcastAgents")
        case (let scope?, false): String(localized: "\(count) \(scope) reset credits", table: "NotchcastAgents")
        case (nil, true): String(localized: "1 reset credit", table: "NotchcastAgents")
        case (nil, false): String(localized: "\(count) reset credits", table: "NotchcastAgents")
        }
    }

    /// Extra usage only with a budget to measure it against: "$166 of $200" left.
    private static func extraMeter(_ extra: AgentExtraUsage) -> AgentMeter? {
        guard let limit = extra.limit, limit > 0, limit.isFinite, extra.used.isFinite else { return nil }
        let share = min(max(extra.used / limit, 0), 1)
        let money = Decimal.FormatStyle.Currency(code: extra.currency, locale: Locale(identifier: "en_US"))
            .precision(.fractionLength(0))
        let remaining = Decimal((1 - share) * limit).formatted(money)
        let of = Decimal(limit).formatted(money)
        return AgentMeter(
            label: String(localized: "Extra usage", table: "NotchcastAgents"), value: percentLeft(share * 100),
            trailing: String(localized: "\(remaining) of \(of)", table: "NotchcastAgents"), fraction: 1 - share,
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

    /// "Weekly, 55 percent left, resets in 5 days 14 hours, runs out in 1 day 17 hours".
    private static func spoken(_ window: AgentWindow, now: Date) -> String {
        let percent = left(window.usedPercent)
        var parts = [label(window), String(localized: "\(percent) percent left", table: "NotchcastAgents")]
        if let resets = window.resetsAt {
            let left = AgentDuration.spoken(resets.timeIntervalSince(now))
            parts.append(String(localized: "resets in \(left)", table: "NotchcastAgents"))
        }
        if let runsOut = AgentPace(window, now: now)?.runsOutIn {
            let left = AgentDuration.spoken(runsOut)
            parts.append(String(localized: "runs out in \(left)", table: "NotchcastAgents"))
        }
        return parts.joined(separator: ", ")
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

    /// "55% left"; used is floored, so only a spent limit reads 0% left.
    static func percentLeft(_ used: Double) -> String {
        String(localized: "\(left(used))% left", table: "NotchcastAgents")
    }

    static func left(_ used: Double) -> Int { 100 - min(whole(used), 100) }

    /// Feed numbers are outside input: a broken or huge one reads 0 or caps rather than trapping `Int`.
    static func whole(_ value: Double) -> Int { value.isFinite ? Int(min(max(value, 0), 1e6).rounded(.down)) : 0 }

    private static func meter(_ window: AgentWindow, now: Date) -> AgentMeter {
        let pace = AgentPace(window, now: now)
        return AgentMeter(
            label: label(window), value: percentLeft(window.usedPercent),
            trailing: window.resetsAt.map { AgentDuration.until($0, now: now) },
            fraction: 1 - window.usedPercent / 100, tick: pace?.tick, thick: window.kind == .weekly && window.scope == nil,
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
        return "\(name) · \(label(window)) \(percentLeft(window.usedPercent))"
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
