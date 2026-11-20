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
let home = URL(fileURLWithPath: "/home/tester")

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

func meters(_ card: AgentCard) -> [AgentMeter] {
    guard case .meters(let meters) = card.body else { fatalError("\(card.title) shows no meters: \(card.body)") }
    return meters
}

/// #1189: a config folder is one path however it is written, and named to Claude Code without a trailing slash.
func folders() {
    let base = ["PATH": "/usr/bin"]
    let slashed = ClaudeLaunch(directory: "/home/me/.claude-work/").environment(base, settings: nil)
    check(slashed["CLAUDE_CONFIG_DIR"] == "/home/me/.claude-work",
          "named without the trailing slash, or Claude Code looks for another Keychain entry")
    let home = URL(fileURLWithPath: "/home/me")
    check(ClaudeLaunch.path("", home: home) == "/home/me/.claude" && ClaudeLaunch.path("~", home: home) == "/home/me"
        && ClaudeLaunch.path("~/.claude_team/", home: home) == "/home/me/.claude_team"
        && ClaudeLaunch.path("/srv/c", home: home) == "/srv/c", "folders compare as one path")
    check(ClaudeLaunch.defaultName(directory: "") == "Claude"
        && ClaudeLaunch.defaultName(directory: "/home/me/.claude_team/") == "claude_team", "Settings' default names")
    check(ClaudeLaunch.name(" ", directory: "~/.claude_team") == "claude_team" && ClaudeLaunch.name(" Team ", directory: "")
        == "Team", "a cleared name becomes the folder's default, a typed one is trimmed")
    print("folders: ok")
}

/// #1189: Settings' default names and the gate's column name the same two config folders.
func boardMatchesFolders() throws {
    func copy(_ name: String, _ folder: String?, used: Int) -> String {
        let folder = folder.map { #""folder": "\#($0)", "# } ?? ""
        return #"{"name": "\#(name)", "provider": "claude", \#(folder)"checkedAt": "2026-11-19T17:55:00Z", "#
            + #""state": "ok", "windows": [{"kind": "weekly", "usedPercent": \#(used), "#
            + #""resetsAt": "2026-11-23T02:00:00Z"}]}"#
    }
    func gate(_ c3: String?, _ c4: String?) throws -> AgentFeedRead {
        .loaded(try AgentFeed.decode(Data((#"{"version": 1, "generatedAt": "2026-11-19T17:59:00Z", "machines": "#
            + #"[{"name": "MBP", "accounts": [\#(copy("C3", c3, used: 40)), \#(copy("C4", c4, used: 60))]}]}"#).utf8)))
    }
    let local = [
        AgentLocalAccount(name: "Claude", provider: "claude",
                          reading: account("Claude", "claude", [weekly(41, resetsIn: 3 * day)], age: minute), folder: ""),
        AgentLocalAccount(name: "claude_team", provider: "claude",
                          reading: account("claude_team", "claude", [], age: minute, state: .signedOut),
                          folder: "~/.claude_team"),
    ]
    let feed = try gate("~/.claude", "~/.claude_team")
    let board = AgentBoard(home: home, machineName: "MBP", local: local, feed: feed, now: now)
    check(board.columns.map { $0.cards.map(\.title) } == [["C3", "C4"]],
          "one card per folder, titled by the gate: \(board.columns.map { $0.cards.map(\.title) })")
    check(meters(board.columns[0].cards[0])[0].value == "59% left", "this Mac's fresh read of ~/.claude wins")
    check(meters(board.columns[0].cards[1])[0].value == "40% left", "a failed local read loses to the gate's copy")

    var slashed = local
    slashed[1].folder = "/home/tester/.claude_team/"
    let added = AgentBoard(home: home, machineName: "MBP", local: slashed, feed: feed, now: now)
    check(added.columns[0].cards.map(\.title) == ["C3", "C4"], "a folder Settings stored with a slash still matches")
    var typed = local
    typed[1].name = "Team"
    let named = AgentBoard(home: home, machineName: "MBP", local: typed, feed: feed, now: now)
    check(named.columns[0].cards.map(\.title) == ["C3", "Team"], "a typed name stays: \(named.columns[0].cards.map(\.title))")
    typed[1].name = ClaudeLaunch.name("  ", directory: "~/.claude_team")
    let cleared = AgentBoard(home: home, machineName: "MBP", local: typed, feed: feed, now: now)
    check(cleared.columns[0].cards.map(\.title) == ["C3", "C4"], "a cleared name is untyped again")
    let twice = local + [AgentLocalAccount(name: "Again", provider: "claude", reading: nil, folder: "~/.claude")]
    let shared = AgentBoard(home: home, machineName: "MBP", local: twice, feed: feed, now: now)
    check(shared.columns[0].cards.map(\.title) == ["C3", "C4", "Again"]
          && shared.columns[0].cards[2].body == .notice(glyph: nil, headline: "Reading…"),
          "#1193: two saved accounts on one folder take the gate's card once: \(shared.columns[0].cards)")
    let elsewhere = AgentBoard(home: home, machineName: "MBA", local: local, feed: feed, now: now)
    check(elsewhere.columns.map { $0.cards.count } == [2, 2], "folders match only in this Mac's own column")
    let old = AgentBoard(home: home, machineName: "MBP", local: local, feed: try gate(nil, nil), now: now)
    check(old.columns[0].cards.map(\.title) == ["Claude", "claude_team", "C3", "C4"],
          "a feed without folders keeps the name match")
    let mixed = try AgentFeed.decode(Data((#"{"version": 1, "generatedAt": "2026-11-19T17:59:00Z", "machines": ["#
        + #"{"name": "MBP", "accounts": [\#(copy("C3", "~/.claude", used: 40)), \#(copy("C4", "~/.claude_team", used: 60))]}, "#
        + #"{"name": "MBA", "accounts": [\#(copy("C1", nil, used: 10)), \#(copy("C2", nil, used: 20))]}]}"#).utf8))
    check(mixed.machines[1].accounts.allSatisfy { $0.folder == nil }, "an old gate's Claude cards carry no folder")
    let onMBA = AgentBoard(home: home, machineName: "MBA",
                           local: [AgentLocalAccount(name: "C1", provider: "claude", reading: nil, folder: ""),
                                   AgentLocalAccount(name: "Claude", provider: "claude", reading: nil, folder: "~/.c2")],
                           feed: .loaded(mixed), now: now)
    check(onMBA.columns.map { $0.cards.map(\.title) } == [["C3", "C4"], ["C1", "Claude", "C2"]],
          "a machine without folders matches by name only: \(onMBA.columns.map { $0.cards.map(\.title) })")
    print("board matches folders: ok")
}

/// #1189: Antigravity's five windows fit a card's three meters, the rest summed up in one line.
func cardCap() {
    func window(_ kind: AgentWindowKind, _ scope: String, _ used: Double) -> AgentWindow {
        AgentWindow(kind: kind, scope: scope, usedPercent: used, resetsAt: now.addingTimeInterval(kind == .session ? hour : day))
    }
    let five = account("Antigravity", "antigravity", [
        window(.weekly, "gemini", 97.1), window(.session, "gemini", 38.5), window(.weekly, "3p", 0),
        window(.session, "3p", 0), window(.weekly, "gemini-argon-wtu", 0),
    ])
    let card = AgentBoard.card(five, now: now)
    check(meters(card).map(\.label) == ["Session · gemini", "Session · 3p", "Weekly · gemini"],
          "the three with least left, in order: \(meters(card).map(\.label))")
    check(card.caption == "2 more, none under 100% left", "the rest in one line: \(String(describing: card.caption))")
    check(card.spoken?.contains("Weekly · gemini-argon-wtu") == true, "VoiceOver still reads every window")
    let four = account("Antigravity", "antigravity", Array(five.windows.prefix(4)))
    check(AgentBoard.card(four, now: now).caption == "1 more, 100% left", "one hidden meter reads as one")
    var old = five
    old.checkedAt = now.addingTimeInterval(-20 * minute)
    check(AgentBoard.card(old, now: now).caption == "Updated 20 min ago", "an old reading's caption comes first")
    let three = AgentBoard.card(account("C1", "claude", [session(10, resetsIn: hour), weekly(20, resetsIn: day),
                                                          weekly(30, resetsIn: day, scope: "Fable")]), now: now)
    check(meters(three).count == 3 && three.caption == nil, "a card at the cap is drawn whole")
    var budget = account("C2", "claude", [session(10, resetsIn: hour), weekly(20, resetsIn: day),
                                           weekly(30, resetsIn: day, scope: "Fable")])
    budget.extraUsage = AgentExtraUsage(used: 90, limit: 100, currency: "USD")
    let extra = AgentBoard.card(budget, now: now)
    check(meters(extra).count == 4 && extra.caption == nil, "Extra usage stays outside the cap")
    let burning = AgentBoard.card(account("C5", "claude", [
        session(45, resetsIn: 4.5 * hour), weekly(70, resetsIn: 1.75 * day), weekly(60, resetsIn: 1.75 * day, scope: "Fable"),
        weekly(50, resetsIn: 1.75 * day, scope: "Sonnet"),
    ]), now: now)
    check(meters(burning).first?.label == "Session" && meters(burning).first?.warning == true,
          "the warning meter is never the one hidden: \(meters(burning).map(\.label))")
    print("card cap: ok")
}

@main
enum AgentsFoldersTest {
    static func main() throws {
        folders()
        try boardMatchesFolders()
        cardCap()
        print("nc-Agents-folders-test: ok")
    }
}
