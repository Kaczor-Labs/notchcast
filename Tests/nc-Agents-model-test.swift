// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift

import Foundation

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError(message()) }
}

let now = Date(timeIntervalSince1970: 1_795_111_200)  // 2026-11-19 18:00 UTC
let minute: TimeInterval = 60
let hour: TimeInterval = 3600
let day: TimeInterval = 86_400

func date(_ text: String) -> Date { AgentTimestamp.parse(text)! }

/// Claude Code 2.1.328's answer for an account with extra usage off; ids, e-mails and the disclaimer removed.
let claudeFixture = #"""
    {"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":null,
    "seven_day":{"utilization":90,"resets_at":"2026-11-23T01:59:59.825376+00:00","limit_dollars":null,
    "used_dollars":null,"remaining_dollars":null,"locked_reason":null},"seven_day_opus":null,
    "seven_day_sonnet":null,"cedar_ember":null,"extra_usage":{"is_enabled":false,"monthly_limit":null,
    "used_credits":null,"utilization":null,"currency":null,"decimal_places":null,"disabled_reason":null,
    "user_disabled":true,"spend_limit_reached":false,"credits_ever_enabled":true,"daily":null,"weekly":null},
    "limits":[{"kind":"weekly_all","group":"weekly","percent":90,"severity":"critical",
    "resets_at":"2026-11-23T01:59:59.825376+00:00","scope":null,"is_active":true},{"kind":"weekly_scoped",
    "group":"weekly","percent":78,"severity":"warning","resets_at":"2026-11-23T01:59:59.825518+00:00",
    "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}],
    "model_scoped":[{"display_name":"Fable","utilization":78,"resets_at":"2026-11-23T01:59:59.825518+00:00"}],
    "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,
    "percent":0,"severity":"normal","enabled":false,"disabled_reason":null,"cap":null,"balance":null,
    "auto_reload":null,"can_purchase_credits":false,"can_toggle":false}}}
    """#

/// Codex CLI 0.170.0's `account/rateLimits/read` for a spent Pro Lite week; the account id removed.
let codexFixture = #"""
    {"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","limitName":null,"normalModelSlug":null,
    "primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1795260977},"secondary":null,
    "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,
    "spendControlReached":false,"planType":"prolite","rateLimitReachedType":null},
    "rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"normalModelSlug":null,
    "primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1795260977},"secondary":null,
    "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,
    "spendControlReached":false,"planType":"prolite","rateLimitReachedType":null}},
    "rateLimitResetCredits":{"availableCount":0,"credits":[]},"rateLimitUpsell":null}
    """#

func claude(_ json: String, observed: Date = now) -> AgentAccount? {
    (try? ClaudeUsageAnswer.decode(Data(json.utf8)))!.account(name: "C1", observed: observed)
}

func codex(_ json: String, observed: Date = now) -> AgentAccount? {
    (try? CodexUsageAnswer.decode(Data(json.utf8)))!.account(name: "Codex", observed: observed)
}

func weekly(_ used: Double, resetsIn: TimeInterval, scope: String? = nil) -> AgentWindow {
    AgentWindow(
        kind: .weekly, scope: scope, usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn), durationMinutes: 10_080)
}

func session(_ used: Double, resetsIn: TimeInterval) -> AgentWindow {
    AgentWindow(kind: .session, usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn), durationMinutes: 300)
}

func account(
    _ name: String, _ provider: String = "claude", _ windows: [AgentWindow], age: TimeInterval = 0,
    state: AgentAccountState = .ok
) -> AgentAccount {
    AgentAccount(name: name, provider: provider, checkedAt: now.addingTimeInterval(-age), state: state, windows: windows)
}

func claudeDecoder() {
    let reading = claude(claudeFixture)!
    check(reading.provider == "claude" && reading.state == .ok && reading.checkedAt == now, "a live reading")
    check(reading.windows.count == 2, "an idle session is no window, Fable is: \(reading.windows)")
    check(reading.windows[0] == AgentWindow(
        kind: .weekly, usedPercent: 90, resetsAt: date("2026-11-23T01:59:59.825376+00:00"), durationMinutes: 10_080),
        "the weekly, with microseconds: \(reading.windows[0])")
    check(reading.windows[1].scope == "Fable" && reading.windows[1].usedPercent == 78
        && reading.windows[1].kind == .weekly, "Fable from model_scoped: \(reading.windows[1])")
    check(reading.extraUsage == nil && reading.resetCredits == nil, "extra usage off, no reset credits")
    check(claude(claudeFixture, observed: date("2026-11-24T00:00:00Z")) == nil,
          "windows that renewed before the reading are no answer")

    let spending = claudeFixture.replacingOccurrences(
        of: #""spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null"#,
        with: #""spend":{"used":{"amount_minor":3412,"currency":"USD","exponent":2},"#
            + #""limit":{"amount_minor":20000,"currency":"USD","exponent":2}"#
    ).replacingOccurrences(
        of: #""percent":0,"severity":"normal","enabled":false"#, with: #""percent":17,"severity":"normal","enabled":true"#)
    check(claude(spending)!.extraUsage == AgentExtraUsage(used: 34.12, limit: 200, currency: "USD"),
          "extra usage in major units: \(String(describing: claude(spending)!.extraUsage))")

    let odd = claudeFixture.replacingOccurrences(of: #""five_hour":null"#, with: #""five_hour":"soon""#)
        .replacingOccurrences(of: #""model_scoped":[{"#, with: #""model_scoped":[7,{"#)
    check(claude(odd)!.windows.map(\.scope) == [nil, "Fable"],
          "a field or entry of an unexpected shape drops alone: \(String(describing: claude(odd)?.windows))")

    let session = claudeFixture.replacingOccurrences(
        of: #""five_hour":null"#, with: #""five_hour":{"utilization":12.5,"resets_at":"2026-11-19T20:00:00+00:00"}"#)
    check(claude(session)!.windows.first == AgentWindow(
        kind: .session, usedPercent: 12.5, resetsAt: date("2026-11-19T20:00:00Z"), durationMinutes: 300),
        "the session window comes first")

    let signedOut = #"{"rate_limits_available":false,"rate_limits":null}"#
    check((try? ClaudeUsageAnswer.decode(Data(signedOut.utf8)))?.signedIn == false && claude(signedOut) == nil,
          "no rate limits means signed out")
    print("claude decoder: ok")
}

func codexDecoder() {
    let reading = codex(codexFixture)!
    let resets = Date(timeIntervalSince1970: 1_795_260_977)
    check(reading.windows == [AgentWindow(kind: .weekly, usedPercent: 100, resetsAt: resets, durationMinutes: 10_080)],
          "one weekly window: \(reading.windows)")
    check(reading.resetCredits == nil, "no banked resets")
    check(reading.isSpent(now: now) && reading.backAt(now: now) == resets, "a spent Codex week")

    let credits = #"""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1795158000000},
        "secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1795600000}},
        "rateLimitResetCredits":{"availableCount":1,"credits":[
        {"id":"a","status":"available","expiresAt":1795900000},{"id":"b","status":"available","expiresAt":1795000000},
        {"id":"c","status":"consumed","expiresAt":1795950000},{"id":"d","expiresAt":1795800000}]}}
        """#
    let banked = codex(credits)!
    check(banked.windows.map(\.kind) == [.session, .weekly], "windows by length: \(banked.windows)")
    check(banked.windows[0].resetsAt == Date(timeIntervalSince1970: 1_795_158_000), "milliseconds read as such")
    check(banked.resetCredits == AgentResetCredits(count: 2, expiresAt: Date(timeIntervalSince1970: 1_795_800_000)),
          "expired and used credits drop, the soonest expiry shows: \(String(describing: banked.resetCredits))")

    let business = #"{"rateLimits":{"primary":null,"individualLimit":{"remainingPercent":35,"resetsAt":1795600000}}}"#
    check(codex(business)!.windows == [AgentWindow(
        kind: .other, usedPercent: 65, resetsAt: Date(timeIntervalSince1970: 1_795_600_000))],
        "a Business allowance as the share left")
    let monthly = #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":5,"windowDurationMins":43200}}}}"#
    check(codex(monthly)!.windows.first?.kind == .monthly, "a 30-day window is monthly")
    let oddBucket = #"{"rateLimitsByLimitId":{"codex_other":7,"codex":{"primary":{"usedPercent":5,"windowDurationMins":300}}}}"#
    check(codex(oddBucket)!.windows.first?.usedPercent == 5, "another model's odd bucket never hides the main one")
    let otherBucket = #"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":5,"windowDurationMins":300}}}"#
    check(codex(otherBucket) == nil, "a model's own bucket never stands in for the main one")
    check((try? JSONDecoder().decode(CodexAccountAnswer.self, from: Data(#"{"account":{"type":"chatgpt"}}"#.utf8)))?
        .signedIn == true, "a ChatGPT sign-in has a plan")
    check((try? JSONDecoder().decode(CodexAccountAnswer.self, from: Data(#"{"account":{"type":"apiKey"}}"#.utf8)))?
        .signedIn == false, "an API key has none")
    check((try? JSONDecoder().decode(CodexAccountAnswer.self, from: Data(#"{"account":null}"#.utf8)))?
        .signedIn == false, "signed out")
    print("codex decoder: ok")
}

func feed() throws {
    let sample = AgentFeed(
        generatedAt: now,
        machines: [AgentMachine(name: "MBA", accounts: [
            AgentAccount(
                name: "C1", provider: "claude", checkedAt: now, state: .ok, windows: [weekly(45, resetsIn: 3 * day)],
                extraUsage: AgentExtraUsage(used: 34, limit: 200, currency: "USD"),
                resetCredits: AgentResetCredits(count: 1, scope: "Fable", expiresAt: now.addingTimeInterval(day)))
        ])],
        shared: [account("Grok", "grok", [], state: .signedOut)])
    let decoded = try AgentFeed.decode(try sample.encoded())
    check(decoded == sample, "a feed survives its own round trip")

    let written = #"""
        {"version":1,"generatedAt":"2026-11-19T18:00:00.250Z","machines":[{"name":"VPS","accounts":[
        {"name":"C6","provider":"claude","checkedAt":"2026-11-19T17:58:00Z","state":"unavailable","windows":[
        {"kind":"weekly","label":"Weekly · Fable","scope":"Fable","usedPercent":12,"resetsAt":"2026-11-22T00:00:00+00:00",
        "durationMinutes":10080}]}]}]}
        """#
    let read = try AgentFeed.decode(Data(written.utf8))
    check(read.shared.isEmpty && read.machines[0].accounts[0].windows[0].label == "Weekly · Fable",
          "`shared` is optional, fractional seconds read")
    do {
        _ = try AgentFeed.decode(Data(written.replacingOccurrences(of: #""version":1"#, with: #""version":2"#).utf8))
        check(false, "version 2 is refused")
    } catch AgentFeedError.unknownVersion(let version) {
        check(version == 2, "the refused version is named")
    }

    let wild = #"""
        {"version":1,"generatedAt":"2026-11-19T18:00:00Z","machines":[{"name":"VPS","accounts":[
        {"name":"C6","provider":"claude","checkedAt":"2026-11-19T17:58:00Z","state":"ok","windows":[
        {"kind":"weekly","usedPercent":1e19,"resetsAt":"2026-11-22T00:00:00Z","durationMinutes":1000000000000},
        {"kind":"session","usedPercent":-1e19,"resetsAt":"2026-11-19T20:00:00Z","durationMinutes":-5}]}]}]}
        """#
    let clamped = try AgentFeed.decode(Data(wild.utf8)).machines[0].accounts[0].windows
    check(clamped.map(\.usedPercent) == [100, 0] && clamped.allSatisfy { $0.durationMinutes == nil },
          "the feed's numbers are held to what a window can be: \(clamped)")
    let board = AgentBoard(
        machineName: "MBA", local: [], feed: .loaded(try AgentFeed.decode(Data(wild.utf8))), now: now)
    check(board.columns.count == 1, "a wild feed still builds a board")
    check(AgentDuration.text(1e300) == AgentDuration.text(.infinity) && AgentDuration.text(.nan) == "1 min",
          "no duration traps")
    print("feed: ok")
}

func pace() {
    let half = weekly(60, resetsIn: 3.5 * day)
    let warned = AgentPace(half, now: now)!
    check(abs(warned.elapsed - 0.5) < 1e-9 && abs(warned.tick! - 0.5) < 1e-9 && warned.warns,
          "60% at half time warns, its tick at what an even pace leaves")
    check(abs(warned.runsOutIn! - 40 * 3.5 * day / 60) < 1, "runs out at the pace so far: \(warned.runsOutIn!)")
    check(warned.runsOutIn! < 3.5 * day, "a warned window runs out before it resets")
    let calm = AgentPace(weekly(40, resetsIn: 3.5 * day), now: now)!
    check(!calm.warns && calm.runsOutIn == nil && calm.tick != nil, "40% at half time is on pace")
    let early = AgentPace(weekly(5, resetsIn: 6.7 * day), now: now)!
    check(early.elapsed < 0.1 && !early.warns && early.tick == nil, "too early to judge or tick")
    let late = AgentPace(weekly(50, resetsIn: 0.01 * day), now: now)!
    check(late.tick == nil, "no tick on the bar's end")
    check(!AgentPace(weekly(100, resetsIn: 3 * day), now: now)!.warns, "a full window no longer warns")
    check(AgentPace(AgentWindow(kind: .other, usedPercent: 50), now: now) == nil, "no length, no pace")
    check(AgentPace(weekly(50, resetsIn: -minute), now: now) == nil, "a renewed window has no pace")
    let tenth = AgentPace(weekly(20, resetsIn: 0.9 * 7 * day), now: now)!
    check(tenth.elapsed == 0.1 && abs(tenth.tick! - 0.9) < 1e-9 && tenth.warns, "a tenth gone ticks at 90% and judges")
    check(!AgentPace(weekly(50, resetsIn: 3.5 * day), now: now)!.warns, "exactly on pace does not warn")
    let end = AgentPace(weekly(50, resetsIn: 0.02 * 7 * day), now: now)!
    check(end.elapsed == 0.98 && end.tick == nil, "no tick from 98% on")
    print("pace: ok")
}

func spent() {
    let mainWeek = account("C1", "claude", [session(30, resetsIn: hour), weekly(100, resetsIn: 2 * day)])
    check(mainWeek.isSpent(now: now) && mainWeek.backAt(now: now) == now.addingTimeInterval(2 * day),
          "Claude's main weekly at 100 spends it")
    check(!account("C1", "claude", [session(100, resetsIn: hour), weekly(50, resetsIn: day)]).isSpent(now: now),
          "Claude's session at 100 does not")
    let fable = account("C1", "claude", [weekly(40, resetsIn: day), weekly(100, resetsIn: 3 * day, scope: "Fable")])
    check(!fable.isSpent(now: now), "nor its Fable weekly")
    let both = account("C1", "claude", [weekly(100, resetsIn: day), weekly(100, resetsIn: 3 * day, scope: "Fable")])
    check(both.backAt(now: now) == now.addingTimeInterval(day), "back when the main weekly renews")
    let codexSession = account("Codex", "codex", [session(100, resetsIn: hour), weekly(70, resetsIn: 2 * day)])
    check(codexSession.isSpent(now: now) && codexSession.backAt(now: now) == now.addingTimeInterval(hour),
          "any other provider is spent by any full window")
    check(!account("C1", "claude", [weekly(100, resetsIn: -minute)]).isSpent(now: now), "a renewed window spends nothing")
    let undated = AgentWindow(kind: .session, usedPercent: 100, durationMinutes: 300)
    check(account("G", "grok", [undated], age: 4 * hour).isSpent(now: now), "an undated session lasts its length")
    check(!account("G", "grok", [undated], age: 6 * hour).isSpent(now: now), "then it goes")
    print("spent: ok")
}

func durations() {
    let cases: [(TimeInterval, String)] = [
        (2 * day + 5 * hour + 59 * minute, "2 d 5 h"), (2 * day + 30 * minute, "2 d"),
        (3 * hour + 20 * minute + 59, "3 h 20 min"),
        (3 * hour + 30, "3 h"), (45 * minute + 59, "45 min"), (59, "1 min"), (0, "1 min"), (-90, "1 min")
    ]
    for (seconds, text) in cases {
        check(AgentDuration.text(seconds) == text, "\(seconds) s reads \(text): \(AgentDuration.text(seconds))")
    }
    check(AgentDuration.until(now.addingTimeInterval(day + 2 * hour), now: now) == "in 1 d 2 h", "until reads in")
    print("durations: ok")
}

func polling() {
    check(AgentPollPolicy.interval(after: nil, repeated: 0, pageShows: true) == 60, "every minute while it shows")
    check(AgentPollPolicy.interval(after: .ok, repeated: 0, pageShows: false) == 300, "every 5 min while hidden")
    let backOff = (1...5).map { AgentPollPolicy.interval(after: .unavailable, repeated: $0, pageShows: true) }
    check(backOff == [300, 600, 1200, 1800, 1800], "unreachable backs off 5 → 30 min: \(backOff)")
    for state in [AgentAccountState.signedOut, .missing, .outdated] {
        check(AgentPollPolicy.interval(after: state, repeated: 1, pageShows: true) == 1800, "\(state) waits for the person")
    }
    check(AgentPollPolicy.isDue(lastAttempt: nil, now: now, failure: nil, repeated: 0, pageShows: false), "never asked")
    check(!AgentPollPolicy.isDue(
        lastAttempt: now.addingTimeInterval(-59), now: now, failure: nil, repeated: 0, pageShows: true), "not yet")
    check(AgentPollPolicy.isDue(
        lastAttempt: now.addingTimeInterval(-60), now: now, failure: nil, repeated: 0, pageShows: true), "due")
    print("polling: ok")
}

func meters(_ card: AgentCard) -> [AgentMeter] {
    guard case .meters(let meters) = card.body else { fatalError("\(card.title) shows no meters: \(card.body)") }
    return meters
}

func notice(_ card: AgentCard) -> (glyph: String?, headline: String) {
    guard case .notice(let glyph, let headline) = card.body else { fatalError("\(card.title) is no notice") }
    return (glyph, headline)
}

func boardThisMacOnly() {
    let c1 = account("C1", "claude", [weekly(78, resetsIn: 3 * day, scope: "Fable"), weekly(30, resetsIn: 3 * day),
                                      session(10, resetsIn: 2 * hour)])
    let spentCodex = account("Codex", "codex", [weekly(100, resetsIn: day + 2 * hour)])
    let board = AgentBoard(
        machineName: "MBA",
        local: [AgentLocalAccount(name: "Codex", provider: "codex", reading: spentCodex),
                AgentLocalAccount(name: "C1", provider: "claude", reading: c1),
                AgentLocalAccount(name: "C2", provider: "claude", reading: nil)],
        feed: .missing, now: now)
    check(board.columns.map(\.title) == ["MBA"] && board.other.isEmpty, "this Mac only")
    check(board.footnote == "This Mac only: no feed found.", "a missing feed is no error: \(String(describing: board.footnote))")
    check(board.columns[0].cards.map(\.title) == ["Codex", "C1", "C2"], "one Mac keeps Settings order, spent or not")
    let card = board.columns[0].cards[1]
    check(!card.hollow && !card.dimmed && card.caption == nil, "a fresh full card")
    check(card.spoken?.contains("Weekly · Fable, 22 percent left, resets in 3 days, runs out in 1 day 3 hours") == true,
          "VoiceOver hears the pace warning: \(String(describing: card.spoken))")
    let rows = meters(card)
    check(rows.map(\.label) == ["Session", "Weekly", "Weekly · Fable"], "session, main weekly, then scoped: \(rows.map(\.label))")
    check(rows[1].thick && !rows[0].thick && !rows[2].thick, "only the main weekly is thick")
    check(rows[2].value == "22% left" && abs(rows[2].fraction - 0.22) < 1e-9 && rows[2].trailing == "in 3 d",
          "Fable fills with the 22% left: \(rows[2])")
    check(rows[2].warning && rows[2].note == "Runs out in 1 d 3 h" && rows[2].fraction < rows[2].tick!,
          "78% of a week in 4 days warns, its fill short of its tick: \(rows[2])")
    check(!rows[1].warning && rows[1].note == nil && rows[1].fraction >= rows[1].tick!, "30% is on pace, past its tick")
    check(notice(board.columns[0].cards[2]).headline == "Reading…", "an account not read yet")
    let spentCard = board.columns[0].cards[0]
    check(spentCard.hollow && notice(spentCard) == ("hourglass", "Back in 1 d 2 h"), "a spent card: \(spentCard)")
    check(board.homeLine == "C1 · Weekly · Fable runs out in 1 d 3 h", "the warned limit: \(String(describing: board.homeLine))")
    print("board, this Mac only: ok")
}

func boardWithFeed() {
    let feed = AgentFeed(
        generatedAt: now,
        machines: [
            AgentMachine(name: "MBP", accounts: [account("C4", "claude", [weekly(20, resetsIn: 5 * day)])]),
            AgentMachine(name: "MBA", accounts: [
                account("C1", "claude", [weekly(40, resetsIn: 5 * day)], age: 0),
                account("C3", "claude", [weekly(10, resetsIn: 5 * day)], age: 26 * minute)]),
            AgentMachine(name: "VPS", accounts: [account("C6", "claude", [weekly(5, resetsIn: 5 * day)])])
        ],
        shared: [account("Grok", "grok", [AgentWindow(kind: .monthly, usedPercent: 3)])])
    let board = AgentBoard(
        machineName: "MBA",
        local: [AgentLocalAccount(name: "C1", provider: "claude",
                                  reading: account("C1", "claude", [weekly(25, resetsIn: 5 * day)], age: minute)),
                AgentLocalAccount(name: "Codex", provider: "codex",
                                  reading: account("Codex", "codex", [], state: .missing))],
        feed: .loaded(feed), now: now)
    check(board.columns.map(\.title) == ["MBP", "MBA", "VPS"] && board.footnote == nil, "machines in feed order")
    check(board.columns[1].cards.map(\.title) == ["C1", "Codex", "C3"], "this Mac's accounts, then the feed's own")
    check(meters(board.columns[1].cards[0])[0].value == "75% left", "this Mac's fresh reading beats the feed's newer one")
    let missing = board.columns[1].cards[1]
    check(missing.hollow && notice(missing) == ("questionmark.app.dashed", "Codex not found"), "a missing CLI")
    let stale = board.columns[1].cards[2]
    check(stale.dimmed && stale.caption == "Updated 26 min ago", "a feed card is stale after 25 min: \(stale)")
    check(board.other.map(\.title) == ["Grok"] && board.other[0].title == "Grok", "shared accounts form the Other row")
    check(meters(board.other[0])[0].label == "Monthly", "an undated monthly")
    check(board.homeLine == "C1 · Weekly 75% left",
          "no warning: the weekly with least left: \(String(describing: board.homeLine))")

    let absent = AgentBoard(
        machineName: "Studio", local: [AgentLocalAccount(name: "C9", provider: "claude", reading: nil)],
        feed: .loaded(feed), now: now)
    check(absent.columns.map(\.title) == ["Studio", "MBP", "MBA", "VPS"], "a Mac the feed lacks comes first")
    let localOnly = AgentBoard(machineName: "VPS", local: [], feed: .loaded(feed), now: now)
    check(localOnly.columns[2].cards.map(\.title) == ["C6"], "a Mac with no local accounts keeps the feed's")
    print("board with a feed: ok")
}

func boardStates() {
    let failed = AgentBoard.card(
        account("C1", "claude", [weekly(40, resetsIn: 5 * day)], age: 25 * minute, state: .unavailable), now: now)
    check(failed.dimmed && !failed.hollow && failed.caption == "Couldn’t refresh · updated 25 min ago",
          "a failed refresh keeps its numbers: \(failed)")
    check(meters(failed)[0].value == "60% left", "the last numbers")
    let recent = AgentBoard.card(
        account("C1", "claude", [weekly(40, resetsIn: 5 * day)], age: 2 * minute, state: .unavailable), now: now)
    check(recent.dimmed && recent.caption == "Couldn’t refresh · updated 2 min ago", "even when recent")
    let cases: [(AgentAccount, String)] = [
        (account("C1", "claude", [], state: .signedOut), "Sign in to Claude Code"),
        (account("C1", "claude", [], state: .missing), "Claude Code not found"),
        (account("C1", "claude", [], state: .outdated), "Update Claude Code"),
        (account("Codex", "codex", [], state: .signedOut), "Sign in to Codex"),
        (account("C1", "claude", [], state: .unavailable), "Couldn’t read usage")
    ]
    for (account, headline) in cases {
        let card = AgentBoard.card(account, now: now)
        check(card.hollow && !card.dimmed && notice(card).headline == headline, "\(headline): \(card)")
    }
    let renewed = AgentBoard.card(
        account("C1", "claude", [session(80, resetsIn: -minute), weekly(30, resetsIn: day)]), now: now)
    check(meters(renewed).map(\.label) == ["Weekly"], "a renewed window goes rather than reading 0%")
    check(AgentBoard.label(AgentWindow(kind: .other, scope: "Credits", usedPercent: 1)) == "Credits", "a scope alone")
    check(AgentBoard.label(AgentWindow(kind: .other, usedPercent: 1)) == "Limit", "nothing to name it by")

    let empty = AgentBoard(machineName: "MBA", local: [], feed: .missing, now: now)
    check(empty.isEmpty && empty.homeLine == nil, "no account and no feed: nothing found")
    check(AgentBoard(machineName: "MBA", local: [], feed: .unreadable, now: now).footnote
        == "This Mac only: the feed couldn’t be read.", "an unreadable feed says so")
    check(AgentBoard(machineName: "MBA", local: [], feed: .unknownVersion(2), now: now).footnote
        == "This Mac only: feed version 2 is newer than this app.", "a newer feed says so")
    print("board states: ok")
}

/// What a card says beyond its bars, and the board as the island page (#1128 part 2).
func cardsAndPage() {
    var c1 = account("C1", "claude", [weekly(20, resetsIn: 5 * day)])
    c1.extraUsage = AgentExtraUsage(used: 34, limit: 200, currency: "USD")
    c1.resetCredits = AgentResetCredits(count: 1, scope: nil, expiresAt: now.addingTimeInterval(day))
    let full = AgentBoard.card(c1, now: now)
    let extra = meters(full).last!
    check(extra.label == "Extra usage" && extra.value == "83% left" && extra.trailing == "$166 of $200" && extra.tick == nil,
          "what is left of the extra-usage budget: \(extra)")
    check(full.credit == "1 reset credit", "a credit in hand")
    check(full.spoken == "C1. 1 reset credit. Weekly, 80 percent left, resets in 5 days. Extra usage, 83% left, $166 of $200",
          "one sentence per card: \(String(describing: full.spoken))")
    c1.extraUsage = AgentExtraUsage(used: 1e30, limit: 1, currency: "USD")
    let huge = meters(AgentBoard.card(c1, now: now)).last!
    check(huge.value == "0% left" && huge.fraction == 0 && huge.trailing == "$0 of $1", "a huge feed number caps: \(huge)")
    c1.extraUsage = AgentExtraUsage(used: -5, limit: 1e300, currency: "USD")
    check(meters(AgentBoard.card(c1, now: now)).last!.value == "100% left", "a negative one floors")
    c1.extraUsage = AgentExtraUsage(used: 5, limit: nil, currency: "USD")
    check(meters(AgentBoard.card(c1, now: now)).count == 1, "no limit, no extra-usage bar")
    check(AgentBoard.percentLeft(100) == "0% left" && AgentBoard.percentLeft(99.5) == "1% left"
              && AgentBoard.percentLeft(0.2) == "100% left", "only a spent limit reads 0% left")
    check(AgentBoard.whole(1e30) == 1_000_000 && AgentBoard.whole(.nan) == 0 && AgentBoard.whole(-.infinity) == 0,
          "no number traps Int")
    check(AgentBoard.credits(AgentResetCredits(count: 2, scope: "Fable", expiresAt: nil), now: now)
              == "2 Fable reset credits", "credits by scope")
    check(AgentBoard.credits(AgentResetCredits(count: 1, scope: nil, expiresAt: now.addingTimeInterval(-minute)), now: now)
              == nil, "a lapsed credit draws nothing")
    check(AgentBoard.credits(AgentResetCredits(count: 0, scope: nil, expiresAt: nil), now: now) == nil, "none in hand")
    let spent = AgentBoard.card(account("Codex", "codex", [weekly(100, resetsIn: 2 * day)]), now: now)
    check(spent.hollow && spent.detail == "Weekly limit used up", "a spent card names its limit: \(spent)")

    let fresh = { (name: String, used: Double) in
        AgentLocalAccount(name: name, provider: "claude",
                          reading: account(name, "claude", [weekly(used, resetsIn: 3 * day)]))
    }
    let feed = AgentFeed(generatedAt: now, machines: [
        AgentMachine(name: "MBP", accounts: [account("C4", "claude", [weekly(100, resetsIn: day)]),
                                             account("C5", "claude", [weekly(5, resetsIn: day)])])
    ], shared: [account("Grok", "grok", [AgentWindow(kind: .monthly, usedPercent: 3)])])
    let two = AgentBoard(machineName: "MBA", local: [fresh("C1", 10)], feed: .loaded(feed), now: now)
    check(two.columns[1].cards.map(\.title) == ["C5", "C4"], "with two Macs a spent account goes last in its column")
    let page = AgentPage.page(two)
    guard case .columns(let groups)? = page.blocks.first, case .cards(let other)? = page.blocks.dropFirst().first else {
        fatalError("columns, then the Other row: \(page.blocks)")
    }
    check(groups.map(\.title) == ["MBA", "MBP"] && groups[1].cards.last?.hollow == true, "a column per Mac")
    check(other.title == "Other" && other.cards.map(\.title) == ["Grok"], "the shared accounts")
    check(page.id == "agents" && page.blocks.count == 2, "no footnote with a feed")

    let one = AgentBoard(machineName: "MBA", local: ["C1", "C2", "C3", "C4"].map { fresh($0, $0 == "C2" ? 100 : 10) },
                         feed: .missing, now: now)
    guard case .columns(let flowed)? = AgentPage.page(one).blocks.first else { fatalError("one Mac's grid") }
    let dealt = flowed.map { group in group.cards.map(\IslandCard.title) }
    check(dealt == [["C1", "C4"], ["C2"], ["C3"]] && flowed.map { $0.title } == ["MBA", "", ""],
          "one Mac deals its cards round the grid: \(dealt)")
    check(flowed[1].cards[0].hollow, "C2 spends in place, in its own column")
    guard case .row(let footnote)? = AgentPage.page(one).blocks.last else { fatalError("the footnote") }
    check(footnote.title == "This Mac only: no feed found.", "the footnote closes the page")

    let empty = AgentPage.page(AgentBoard(machineName: "MBA", local: [], feed: .missing, now: now))
    guard case .row(let none)? = empty.blocks.first else { fatalError("the empty state") }
    check(none.title == "No plans found" && empty.line.text == "No plans found", "no accounts says so")
    print("cards and page: ok")
}

func claudeLaunch() {
    let base = ["PATH": "/usr/bin", "CLAUDE_CODE_ENTRYPOINT": "x", "ANTHROPIC_API_KEY": "k", "CLAUDECODE": "1",
                "DISABLE_TELEMETRY": "1", "CLAUDE_CONFIG_DIR": "/elsewhere", "HOME": "/home/me"]
    let settings = Data(#"{"env":{"HTTPS_PROXY":"http://proxy:8080","DISABLE_ERROR_REPORTING":true,"NO_PROXY":1,"OTHER":"x"}}"#.utf8)
    let own = ClaudeLaunch(directory: "").environment(base, settings: nil)
    check(own == ["PATH": "/usr/bin", "DISABLE_TELEMETRY": "1", "HOME": "/home/me", "DISABLE_AUTOUPDATER": "1"],
          "the app's own Claude variables never reach the check: \(own)")
    let chosen = ClaudeLaunch(directory: "/home/me/.claude-work").environment(base, settings: settings)
    check(chosen["CLAUDE_CONFIG_DIR"] == "/home/me/.claude-work", "a chosen folder is named")
    check(chosen["HTTPS_PROXY"] == "http://proxy:8080" && chosen["DISABLE_ERROR_REPORTING"] == "true"
        && chosen["NO_PROXY"] == "1" && chosen["OTHER"] == nil, "settings' opt-outs and proxy apply: \(chosen)")
    let home = URL(fileURLWithPath: "/home/me")
    check(ClaudeLaunch(directory: "").profileURL(home: home).path == "/home/me/.claude.json", "the default profile")
    check(ClaudeLaunch(directory: "/home/me/.claude-work").profileURL(home: home).path
        == "/home/me/.claude-work/.claude.json", "a chosen folder's profile")
    let profile = ClaudeLaunch.Profile(
        Data(#"{"oauthAccount":{"accountUuid":"a"},"cachedUsageUtilization":{"fetchedAtMs":1795111200000}}"#.utf8))
    check(profile.usageFetched == now && profile.identity == ["a", nil, nil], "the profile's fetch time")
    check(ClaudeLaunch.Profile(nil) == ClaudeLaunch.Profile(Data("{}".utf8)), "no profile reads as empty")
    print("claude launch: ok")
}

/// A `gate.py feed` cut to one window each, its machines read `now` less 20 min.
let gateFeed = #"""
    {"version": 1, "generatedAt": "2026-11-19T17:59:00Z", "machines": [
    {"name": "MBA", "accounts": [{"name": "C1", "provider": "claude", "checkedAt": "2026-11-19T17:40:00Z",
    "windows": [{"kind": "weekly", "label": "Weekly", "scope": null, "usedPercent": 93,
    "resetsAt": "2026-11-23T02:00:00Z", "durationMinutes": 10080}], "state": "ok",
    "resetCredits": {"count": 1, "expiresAt": "2026-12-01T00:00:00Z"}},
    {"name": "C2", "provider": "claude", "checkedAt": "2026-11-19T17:40:00Z", "windows": [], "state": "signedOut",
    "resetCredits": null}]},
    {"name": "MBP", "accounts": [{"name": "C3", "provider": "claude", "checkedAt": "2026-11-19T17:40:00Z",
    "windows": [{"kind": "weekly", "label": "Weekly", "scope": null, "usedPercent": 40,
    "resetsAt": "2026-11-23T02:00:00Z", "durationMinutes": 10080}], "state": "ok", "resetCredits": null}]},
    {"name": "VPS", "accounts": [{"name": "C5", "provider": "claude", "checkedAt": "2026-11-19T17:40:00Z",
    "windows": [{"kind": "session", "label": "Session", "scope": null, "usedPercent": 19,
    "resetsAt": "2026-11-19T19:00:00Z", "durationMinutes": 300}], "state": "ok", "resetCredits": null}]}],
    "shared": [{"name": "Codex", "provider": "codex", "checkedAt": "2026-11-19T17:55:00Z",
    "windows": [{"kind": "weekly", "label": "Weekly", "scope": null, "usedPercent": 30,
    "resetsAt": "2026-11-23T02:00:00Z", "durationMinutes": 10080}], "state": "ok",
    "resetCredits": {"count": 2, "expiresAt": "2026-12-01T00:00:00Z"}},
    {"name": "Grok", "provider": "grok", "checkedAt": "2026-11-19T17:40:00Z", "windows": [{"kind": "monthly",
    "label": "Monthly", "scope": null, "usedPercent": 3, "resetsAt": null, "durationMinutes": null}],
    "state": "ok", "resetCredits": null}]}
    """#

/// #1169: the gate's feed beside this Mac's own readings.
func boardWithGateFeed() throws {
    let feed = try AgentFeed.decode(Data(gateFeed.utf8))
    var codex = account("Codex", "codex", [weekly(50, resetsIn: 3 * day)], age: 30 * minute)
    codex.extraUsage = AgentExtraUsage(used: 34, limit: 200, currency: "USD")
    var c1 = account("C1", "claude", [weekly(90, resetsIn: 3 * day)], age: 2 * minute)
    c1.extraUsage = AgentExtraUsage(used: 10, limit: 100, currency: "USD")
    let local = [AgentLocalAccount(name: "C1", provider: "claude", reading: c1),
                 AgentLocalAccount(name: "Codex", provider: "codex", reading: codex)]
    let board = AgentBoard(machineName: "MBA", local: local, feed: .loaded(feed), now: now)
    check(board.columns.map(\.title) == ["MBA", "MBP", "VPS"], "the gate's machines: \(board.columns.map(\.title))")
    check(board.columns[0].cards.map(\.title) == ["C1", "C2"], "Codex leaves this Mac's column")
    check(board.other.map(\.title) == ["Codex", "Grok"], "one Codex, in Other: \(board.other.map(\.title))")
    let shared = board.other[0]
    check(meters(shared)[0].value == "70% left" && !shared.dimmed, "the feed's fresher Codex wins: \(shared)")
    check(shared.credit == "2 reset credits" && meters(shared).last?.trailing == "$166 of $200",
          "extra usage carries over from this Mac's older Codex: \(shared)")
    let mine = board.columns[0].cards[0]
    check(meters(mine)[0].value == "10% left" && mine.credit == "1 reset credit" && !mine.dimmed,
          "this Mac's fresh C1 wins and keeps the feed's credit: \(mine)")
    check(meters(mine).last?.trailing == "$90 of $100", "and its own extra usage")
    let remote = board.columns.dropFirst().flatMap(\.cards) + [board.other[1]]
    check(remote.allSatisfy { !$0.dimmed && $0.caption == nil }, "nothing from the feed dims at 20 min: \(remote)")
    let local20 = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(
        name: "C9", provider: "claude", reading: account("C9", "claude", [weekly(5, resetsIn: day)], age: 20 * minute))],
                             feed: .loaded(feed), now: now)
    check(local20.columns[0].cards.first { $0.title == "C9" }?.dimmed == true, "this Mac's own reading still dims after 10 min")

    let renamed = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(name: "OpenAI", provider: "codex", reading: codex)],
                             feed: .loaded(feed), now: now)
    check(renamed.other.map(\.title) == ["Codex", "Grok"] && !renamed.columns[0].cards.contains { $0.title == "OpenAI" },
          "one of a provider on each side matches though the names differ")
    var failed = codex
    failed.state = .unavailable
    failed.checkedAt = now.addingTimeInterval(-minute)
    var ownFresh = codex
    ownFresh.checkedAt = now.addingTimeInterval(-minute)
    ownFresh.extraUsage = nil
    for (reading, used, why) in [(failed, "70% left", "a failed local read loses"), (ownFresh, "50% left", "a fresh one wins")] {
        let pair = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(name: "Codex", provider: "codex", reading: reading)],
                              feed: .loaded(feed), now: now)
        check(meters(pair.other[0])[0].value == used && pair.other[0].credit == "2 reset credits", "\(why): \(pair.other[0])")
    }

    let later = now.addingTimeInterval(25 * minute)
    var spent = codex
    spent.checkedAt = later.addingTimeInterval(-minute)
    spent.extraUsage = nil
    let lent = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(name: "Codex", provider: "codex", reading: spent)],
                          feed: .loaded(feed), now: later)
    check(meters(lent.other[0])[0].value == "50% left" && lent.other[0].credit == nil,
          "a stale feed copy lends no credit: \(lent.other[0])")
    var broken = feed
    broken.shared[0].state = .unavailable
    broken.shared[0].windows = []
    let kept = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(name: "Codex", provider: "codex", reading: failed)],
                          feed: .loaded(broken), now: now)
    check(meters(kept.other[0])[0].value == "50% left", "a failed local read keeps its numbers beside a failed copy")
    let edge = AgentBoard(machineName: "MBP", local: [], feed: .loaded(feed), now: now.addingTimeInterval(5 * minute))
    let past = AgentBoard(machineName: "MBP", local: [], feed: .loaded(feed), now: now.addingTimeInterval(5 * minute + 1))
    check(edge.columns.first { $0.title == "VPS" }?.cards[0].dimmed == false, "a feed reading at 25 min still counts")
    check(past.columns.first { $0.title == "VPS" }?.cards[0].dimmed == true, "and dims just past it")
    let ownEdge = AgentBoard(machineName: "MBA", local: [AgentLocalAccount(
        name: "C9", provider: "claude", reading: account("C9", "claude", [weekly(5, resetsIn: day)], age: 10 * minute))],
                             feed: .missing, now: now)
    check(ownEdge.columns[0].cards[0].dimmed == false, "this Mac's own reading at 10 min still counts")
    print("board with the gate's feed: ok")
}

@main
enum AgentsModelTest {
    static func main() throws {
        claudeDecoder()
        codexDecoder()
        try feed()
        pace()
        spent()
        durations()
        polling()
        boardThisMacOnly()
        boardWithFeed()
        try boardWithGateFeed()
        boardStates()
        cardsAndPage()
        claudeLaunch()
        print("nc-Agents-model-test: ok")
    }
}
