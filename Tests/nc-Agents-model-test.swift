// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-reads: Tests/nc-Agents-feeds/*.json
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Agents-model-test: \(message)") }
}

func file(_ json: String) -> AgentsFeedFile { .data(Data(json.utf8)) }

func sample(_ name: String) -> AgentsFeedFile {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "nc-Agents-feeds/\(name)")
    guard let data = try? Data(contentsOf: url) else { fatalError("nc-Agents-model-test: no sample \(name)") }
    return .data(data)
}

func date(_ text: String) -> Date {
    guard let date = try? Date(text, strategy: .iso8601) else { fatalError("nc-Agents-model-test: date \(text)") }
    return date
}

func rows(_ page: IslandPage?) -> [IslandPageRow] {
    page?.blocks.compactMap { block -> IslandPageRow? in
        if case .row(let row) = block { return row }
        return nil
    } ?? []
}

func meters(_ page: IslandPage?) -> [IslandPageMeter] {
    page?.blocks.compactMap { block -> IslandPageMeter? in
        if case .meter(let meter) = block { return meter }
        return nil
    } ?? []
}

let region = AgentsRegion(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

func board(agents: AgentsFeedFile = sample(AgentsFeed.fileName), usage: AgentsFeedFile = sample(UsageFeed.fileName),
           at now: String) -> AgentsBoard {
    let now = date(now)
    return AgentsBoard(agents: AgentsFeed.read(agents, now: now), usage: UsageFeed.read(usage, now: now), now: now,
                       region: region)
}

/// The feed reader as a model (#976): parsing, limits, staleness, the page, the badge and the closed island.
@main
struct AgentsModelTest {
    static func main() {
        sampleFeeds()
        samplePage()
        staleness()
        unreadable()
        limits()
        links()
        closedIsland()
        asks()
        overflow()
        print("AgentsModelTest passed")
    }

    static func sampleFeeds() {
        let live = board(at: "2026-11-18T10:01:00Z")
        guard let agents = live.agents.live, let usage = live.usage.live else { return check(false, "samples read live") }
        check(agents.agents.map(\.id) == ["atlas", "birch", "cedar", "dune", "ember", "fern"], "six sample agents")
        check(agents.staleAfter == 120 && agents.openURL?.host() == "agents.example", "the feed's own fields")
        check(agents.agents[1].role == .worker && agents.agents[1].parent == "atlas" && agents.agents[1].needsInput,
              "a worker under its coordinator, asking")
        check(agents.agents[3].openURL?.scheme == "exampleagents", "an app URL scheme is a link")
        check(usage.meters.map(\.percentLeft) == [62, 41.5, 9] && usage.meters[2].warnBelow == 10, "three meters")
        check(live.waiting.map(\.id) == ["birch", "dune"] && live.working == 2, "two wait, two work")
        check(live.lowest?.id == "quartz-month", "the lowest meter is the plan closest to running out")
        let fraction = #"{"schema":"notchcast.usage/1","updatedAt":"2026-11-18T10:00:00.250Z","meters":[]}"#
        check(UsageFeed.read(file(fraction), now: date("2026-11-18T10:00:01Z")).live != nil, "fractional seconds read")
    }

    static func samplePage() {
        let live = board(at: "2026-11-18T10:01:00Z")
        guard let page = live.page else { return check(false, "the samples make a page") }
        check(page.id == "agents" && page.order == 0 && page.badge == 2, "the Agents page leads, badged with who waits")
        check(page.line.text == "2 agents waiting" && page.line.detail == "AI plan 9% left",
              "Home: who waits, then the lowest plan: \(page.line)")
        let listed = rows(page)
        check(listed.map(\.title) == ["Changelog draft", "Import pipeline", "Release notes", "Screenshot refresh",
                                      "Parser tests"], "asking first, then coordinator above workers: \(listed)")
        check(listed[0].detail == "Ship as 2.4 or 3.0?" && listed[0].trailing == "Open" && listed[0].id == "open:birch",
              "an asking row shows the ask in plain words and opens")
        check(listed[2].symbol == "person.2" && listed[2].detail == "Lighthouse · Collecting merged changes",
              "a coordinator row names its group and what it does")
        check(listed[3].symbol == "arrow.turn.down.right" && listed[3].trailing?.contains("15m") == true,
              "a worker sits under its coordinator with its time: \(listed[3])")
        check(listed[4].symbol == "exclamationmark.triangle" && listed[4].trailing?.contains("1h") == true,
              "a failed worker of an asking coordinator still lists: \(listed[4])")
        check(!listed.contains { $0.title == "Docs sweep" }, "a finished agent is not listed")
        let bars = meters(page)
        check(bars.map(\.label) == ["North · session", "North · week", "Quartz · second account"],
              "a bar for every meter, all plans and accounts")
        check(bars[0].fraction == 0.62 && bars[0].value.hasPrefix("62% left") && bars[0].value.contains("3h"),
              "percent left and the reset time: \(bars[0].value)")
        check(bars[1].value.hasPrefix("41% left"), "percent left rounds down: \(bars[1].value)")
        check(bars[2].value.contains("12d"), "a far reset counts days: \(bars[2].value)")
        check(live.url(for: "open:birch")?.absoluteString == "https://agents.example/birch", "an agent's own link")
        check(live.url(for: "open:cedar")?.absoluteString == "https://agents.example/board", "else the feed's")
        check(live.url(for: "open:nobody") == nil && live.url(for: IslandPage.refreshAction) == nil, "nothing else opens")
        let calm = board(agents: .missing, at: "2026-11-18T10:01:00Z")
        check(calm.page?.line.text == "AI plan 9% left" && calm.page?.badge == 0, "with no agents, the plan is the line")
        check(rows(calm.page).isEmpty && meters(calm.page).count == 3, "and the page is the bars alone")
        let one = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","agents":[{"id":"a","title":"A","#
            + #""needsInput":true}]}"#
        let single = board(agents: file(one), usage: .missing, at: "2026-11-18T10:01:00Z")
        check(single.page?.line.text == "1 agent waiting" && single.page?.line.detail == nil, "one agent is singular")
        check(rows(single.page)[0].detail == "Waiting for you" && rows(single.page)[0].id == nil
              && rows(single.page)[0].trailing == nil, "an ask with no words and no link is plain text")
    }

    static func staleness() {
        check(board(at: "2026-11-18T10:01:59Z").agents.live != nil, "live until staleAfter has passed")
        let stale = board(at: "2026-11-18T10:02:00Z")
        check(stale.agents.live == nil && stale.agents.feed != nil && stale.usage.live != nil, "agents stale, usage live")
        check(stale.waiting.isEmpty && stale.page?.badge == 0, "a stale ask is never shown as live")
        check(stale.status?.rank == .lowPlan, "so the closed island falls back to the plan")
        let first = rows(stale.page)[0]
        check(first.title == "Stale" && first.detail?.contains("10:00") == true, "marked stale with its time: \(first)")
        check(rows(stale.page).count == 6, "its last agents stay listed under the mark")
        let old = board(at: "2026-11-20T10:00:00Z")
        check(old.usage.live == nil && rows(old.page).filter { $0.title == "Stale" }.count == 2, "both stale, both marked")
        check(rows(old.page)[0].detail?.contains("Nov 18") == true, "an older reading names its day")
        check(old.page?.line.text == "Stale" && old.status == nil && meters(old.page).count == 3, "last values, no badge")
        check(board(at: "2026-11-18T10:01:00Z").nextRefresh == 60, "the next look is when the agents feed goes stale")
        check(board(at: "2026-11-18T10:01:30Z").nextRefresh == 30, "counted from now")
        check(stale.nextRefresh == 60, "then once a minute, for the times on the page")
        check(board(agents: .missing, usage: .missing, at: "2026-11-18T10:01:00Z").nextRefresh == nil, "nothing to wait for")
        check(board(at: "2026-11-18T09:58:01Z").agents.live != nil, "a helper clock a little ahead of ours is still live")
        check(board(at: "2026-11-18T09:58:00Z").agents.live == nil, "a feed dated staleAfter ahead is stale")
    }

    static func unreadable() {
        let now = date("2026-11-18T10:01:00Z")
        check(AgentsFeed.read(.missing, now: now) == .missing && UsageFeed.read(.missing, now: now) == .missing, "missing")
        let unreadable: [AgentsFeedFile] = [
            .tooLarge, file("{ not json"), file("[1, 2]"), file(""), file(#"{"schema":"notchcast.agents/2"}"#),
                    file(#"{"schema":"notchcast.agents/1","agents":[]}"#),
                    file(#"{"schema":"notchcast.agents/1","updatedAt":"yesterday","agents":[]}"#),
                    file(#"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","agents":{}}"#),
                    .data(Data(count: AgentsFeedFile.maxBytes + 1))]
        for bad in unreadable {
            check(AgentsFeed.read(bad, now: now) == .unreadable, "unreadable: \(bad)")
        }
        check(UsageFeed.read(sample(AgentsFeed.fileName), now: now) == .unreadable, "the other feed's schema is refused")
        let none = board(agents: .missing, usage: .missing, at: "2026-11-18T10:01:00Z")
        check(none.page == nil && none.status == nil, "no files: no tab and no badge")
        let broken = board(agents: file("{"), usage: .tooLarge, at: "2026-11-18T10:01:00Z")
        check(rows(broken.page).map(\.title) == ["No data", "No data"] && broken.page?.line.text == "No data",
              "a malformed or oversized file is a calm No data")
        check(rows(broken.page).map(\.detail) == ["agents.json could not be read", "usage.json could not be read"],
              "naming the file")
    }

    static func limits() {
        let now = date("2026-11-18T10:00:30Z")
        let many = (0..<150).map { #"{"id":"a\#($0)","title":"T\#($0)"}"# }.joined(separator: ",")
        let long = String(repeating: "x", count: 500)
        let json = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","staleAfter":0,"surprise":[1],"#
            + #""agents":[{"id":"long","title":"\#(long)","ask":"line one\nline two","role":"captain","status":"napping","#
            + #""needsInput":"yes","since":12,"extra":{"a":1}},{"title":"no id"},{"id":"no title"},7,\#(many)]}"#
        guard let feed = AgentsFeed.read(file(json), now: now).feed else { return check(false, "a lenient read") }
        check(feed.agents.count == AgentsFeed.maxAgents - 3, "the first 100 entries count, less the bad ones")
        let first = feed.agents[0]
        check(first.title.count == 80 && first.title.hasSuffix("…"), "a long title is cut")
        check(first.ask == "line one line two", "text is one line")
        check(first.role == .agent && first.status == .idle && !first.needsInput && first.since == nil,
              "unknown values and wrong types read as the calm defaults")
        check(feed.staleAfter == 5, "staleAfter has a floor")
        check(AgentsFeed.read(file(json), now: now) == .stale(feed), "and applies")
        let usage = #"{"schema":"notchcast.usage/1","updatedAt":"2026-11-18T10:00:00Z","meters":["#
            + #"{"label":"Over","percentLeft":140},{"label":"Under","percentLeft":-3,"warnBelow":250},"#
            + #"{"label":"Flag","percentLeft":true},{"label":"Text","percentLeft":"62"},{"percentLeft":50}]}"#
        guard let read = UsageFeed.read(file(usage), now: now).live else { return check(false, "usage read") }
        check(read.staleAfter == 300, "a missing staleAfter is five minutes")
        check(read.meters.map(\.percentLeft) == [100, 0] && read.meters[1].warnBelow == 100, "percent stays in 0...100")
        check(read.meters.map(\.id) == ["Over", "Under"], "a meter without an id is known by its label; no label, no meter")
    }

    static func links() {
        func link(_ text: String) -> URL? {
            let json = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","openURL":"\#(text)","agents":[]}"#
            return AgentsFeed.read(file(json), now: date("2026-11-18T10:00:30Z")).feed?.openURL
        }
        check(link("https://agents.example/a") != nil && link("exampleagents://thread/1") != nil, "https and app schemes")
        for refused in ["http://agents.example", "file:///etc/hosts", "javascript:alert(1)", "FILE:///etc/hosts",
                        "data:text/html,x", "ssh://host", "smb://host/share", "https:///nohost", "no scheme", "",
                        "facetime:a@b.example", "facetime-audio:a@b.example", "tel:112", "sms:112", "mailto:a@b.example"] {
            check(link(refused) == nil, "refused: \(refused)")
        }
        check(link("https://agents.example/" + String(repeating: "a", count: 2100)) == nil, "an overlong link is refused")
    }

    static func closedIsland() {
        let live = board(at: "2026-11-18T10:01:00Z")
        check(live.status == IslandStatus(id: "agents", symbol: "questionmark.bubble", text: "2",
                                          label: "2 agents waiting", rank: .agentWaiting),
              "beside the notch: a glyph and a short number")
        let plan = board(agents: .missing, at: "2026-11-18T10:01:00Z").status
        check(plan?.text == "9%" && plan?.label == "AI plan 9% left" && plan?.rank == .lowPlan,
              "no one waiting: the plan under its warning line")
        let roomy = #"{"schema":"notchcast.usage/1","updatedAt":"2026-11-18T10:00:00Z","meters":["#
            + #"{"label":"A","percentLeft":21},{"label":"B","percentLeft":12,"warnBelow":10}]}"#
        check(board(agents: .missing, usage: file(roomy), at: "2026-11-18T10:01:00Z").status == nil,
              "above its warning line, 20% unless the meter says, a plan shows nothing")
        let order: [IslandRestRank] = [.plain, .lowPlan, .systemHot, .music, .meeting, .agentWaiting]
        check(order == order.sorted(), "946-3: agent waiting > meeting > music > system hot > low AI plan")
        func status(_ id: String, _ rank: IslandRestRank) -> IslandStatus {
            IslandStatus(id: id, symbol: "circle", label: id, rank: rank)
        }
        let mixed = [status("agents", .agentWaiting), status("update", .plain), status("plan", .lowPlan),
                     status("other", .plain)]
        check(IslandRestRank.ordered(mixed).map(\.id) == ["update", "other", "plan", "agents"],
              "the highest rank ends the row, where the pill keeps and taps it; equals keep posting order")
        check(IslandRestRank.hidesGlance(mixed), "a waiting agent takes the pill from the meeting glance")
        check(!IslandRestRank.hidesGlance([status("music", .music), status("plan", .lowPlan), status("m", .meeting)]),
              "nothing below the meeting does")
        check(IslandStatus(id: "x", symbol: "circle", label: "x").rank == .plain, "a status posted as before ranks plain")
    }

    static func asks() {
        let live = board(at: "2026-11-18T10:01:00Z")
        var log = AgentsAskLog()
        let first = log.fresh(in: live.waiting)
        check(first.map(\.id) == ["birch", "dune"], "both asks are new")
        check(AgentsBoard.notice(for: first)?.text == "2 agents need you", "several at once share one line")
        check(log.fresh(in: live.waiting).isEmpty && AgentsBoard.notice(for: []) == nil, "shown once, then only the badge")
        let birch = live.waiting[0]
        check(log.fresh(in: [birch]).isEmpty, "one answered: nothing new")
        let again = log.fresh(in: live.waiting)
        check(again.map(\.id) == ["dune"], "asking again after an answer is a new request")
        let notice = AgentsBoard.notice(for: again)
        check(notice?.text == "Agent needs you: Import pipeline" && notice?.id == "agents.ask", "the line names it")
        check(notice?.dwell == 2.4 && notice?.isHeadline == true, "2.4 s, and below the notch on a notched display")
        var changed = birch
        changed.ask = "And the date?"
        check(log.fresh(in: [changed, live.waiting[1]]).map(\.id) == ["birch"], "a different question is new too")
    }

    static func overflow() {
        let many = (0..<12).map { #"{"id":"w\#($0)","title":"Worker \#($0)","status":"working"}"# }.joined(separator: ",")
        let json = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","agents":["#
            + #"{"id":"ask","title":"Asker","needsInput":true},\#(many)]}"#
        let crowded = board(agents: file(json), usage: .missing, at: "2026-11-18T10:00:30Z")
        let listed = rows(crowded.page)
        check(listed.count == AgentsBoard.maxRows && listed[0].title == "Asker", "at most eight rows, asking first")
        check(listed.last?.title == "6 more" && listed.last?.id == nil, "the rest are counted: \(listed.last?.title ?? "")")
        check(crowded.page?.line.detail == nil && crowded.page?.line.text == "1 agent waiting", "no plan, no detail")
        let loop = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:00Z","agents":["#
            + #"{"id":"a","title":"A","parent":"b","status":"working"},{"id":"b","title":"B","parent":"a","status":"working"},"#
            + #"{"id":"c","title":"C","parent":"gone","status":"working"}]}"#
        check(Set(rows(board(agents: file(loop), usage: .missing, at: "2026-11-18T10:00:30Z").page).map(\.title))
              == ["A", "B", "C"], "a parent loop or a missing parent still lists everyone once")
    }
}
