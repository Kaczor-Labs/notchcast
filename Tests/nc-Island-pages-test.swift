// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandCardSlots.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageSwipe.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
import CoreGraphics
import Foundation

/// The open island's pages as a model (#975): which tabs exist, what hover opens, badges and sizes.
@main
@MainActor
struct IslandPagesTest {
    typealias Tab = IslandPageDeck.Tab

    static func page(_ id: String, order: Int, badge: Int = 0) -> IslandPage {
        IslandPage(id: id, title: id.capitalized, symbol: "circle", order: order, badge: badge,
                   line: IslandPageLine(text: id), blocks: [.row(IslandPageRow(title: id))])
    }

    static func deck(_ pages: IslandPage...) -> IslandPageDeck {
        var deck = IslandPageDeck()
        for page in pages { deck.set(page, id: page.id) }
        return deck
    }

    static func main() {
        tabs()
        singleModule()
        homeOrder()
        selection()
        visibility()
        notice()
        focus()
        sizing()
        swipe()
        keys()
        player()
        cards()
        print("IslandPagesTest passed")
    }

    static func tabs() {
        precondition(IslandPageDeck().tabs == [.home] && IslandPageDeck().selection == .home
            && !IslandPageDeck().showsTabBar && IslandPageDeck().current == nil, "no module: an empty Home, no tab bar")
        let three = deck(page("day", order: 30), page("player", order: 10), page("agents", order: 0))
        precondition(three.tabs == [.home, .page("agents"), .page("player"), .page("day")], "Home, then by order")
        precondition(three.showsTabBar, "two or more pages get the tab bar")
        let five = deck(page("agents", order: 0), page("player", order: 10), page("system", order: 20),
                        page("day", order: 30), page("extra", order: 40))
        precondition(five.tabs.count == 6 && five.homeLines.count == 5, "five modules: Home plus five tabs, five lines")
        var off = three
        off.set(nil, id: "player")
        precondition(off.tabs == [.home, .page("agents"), .page("day")] && off.page("player") == nil,
                     "a module turned off or out of data leaves no tab")
        precondition(!off.homeLines.contains { $0.id == "player" }, "and no Home line")
        var replaced = three
        replaced.set(page("ignored", order: 99), id: "agents")
        precondition(replaced.pages.filter { $0.id == "agents" }.count == 1 && replaced.page("agents")?.order == 99,
                     "a repost replaces its owner's page, keyed by the owner")
        precondition(replaced.tabs.last == .page("agents"), "and takes its new order")
    }

    static func singleModule() {
        var one = deck(page("player", order: 10))
        precondition(one.tabs == [.page("player")] && !one.showsTabBar, "one module: no Home, no tab bar")
        one.open()
        precondition(one.selection == .page("player") && one.current?.id == "player", "hover opens its page directly")
        one.set(page("agents", order: 0, badge: 1), id: "agents")
        precondition(one.showsTabBar && one.selection == .home, "a second module brings Home back")
    }

    static func homeOrder() {
        let calm = deck(page("day", order: 30), page("player", order: 10), page("agents", order: 0))
        precondition(calm.homeLines.map(\.id) == ["agents", "player", "day"], "Home follows the page order")
        let waiting = deck(page("player", order: 10), page("day", order: 30, badge: 2), page("agents", order: 0))
        precondition(waiting.homeLines.map(\.id) == ["day", "agents", "player"], "a page waiting for the user leads")
        precondition(waiting.page("day")?.badge == 2 && waiting.page("player")?.badge == 0, "badges are counts")
        precondition(waiting.tabs == [.home, .page("agents"), .page("player"), .page("day")],
                     "tabs never reorder for a badge")
    }

    static func selection() {
        var three = deck(page("agents", order: 0), page("player", order: 10), page("day", order: 30))
        precondition(three.selection == .home && three.current == nil, "hover opens Home")
        three.select(.page("player"))
        precondition(three.current?.id == "player", "a tab click or a Home line opens that page")
        three.open()
        precondition(three.selection == .home, "the next hover opens Home again")
        three.select(.page("missing"))
        precondition(three.selection == .home, "a tab that does not exist is ignored")
        three.select(number: 3)
        precondition(three.selection == .page("player"), "3 is the third tab")
        three.select(number: 9)
        precondition(three.selection == .page("player"), "a number past the last tab does nothing")
        three.move(by: 1)
        three.move(by: 1)
        precondition(three.selection == .page("day"), "the arrow stops at the last tab")
        three.move(by: -9)
        precondition(three.selection == .home, "and at the first")
        three.select(.page("day"))
        three.set(nil, id: "day")
        precondition(three.selection == .home, "a page that goes away falls back to Home")
        three.select(.page("player"))
        three.set(nil, id: "agents")
        precondition(three.selection == .page("player") && !three.showsTabBar, "the last page left shows alone")
    }

    static func visibility() {
        var two = deck(page("player", order: 10), page("day", order: 30))
        var audience = IslandPageAudience()
        let watchers = ["day", "player", "system"]
        func told(_ open: Bool) -> [String] {
            audience.changes(watchers: watchers, open: open, deck: two).map { "\($0.id)=\($0.visible)" }
        }
        precondition(told(false).isEmpty, "a closed island tells nobody")
        precondition(told(true) == ["day=true", "player=true", "system=true"],
                     "Home shows every page's data, and a watcher with no page yet may post one")
        precondition(told(true).isEmpty, "each change is told once")
        two.select(.page("day"))
        precondition(told(true) == ["player=false"], "on Day's page only the other page's data goes out of sight")
        two.set(nil, id: "player")
        precondition(told(true) == ["player=true"], "a watcher whose page went is asked again")
        audience.forget("day")
        precondition(told(true) == ["day=true"], "a watcher registered again while open is told again")
        precondition(told(false) == ["day=false", "player=false", "system=false"], "closing hides them all")
    }

    /// #1005's rule: a page never hides a notice, and a page is always one click away.
    static func notice() {
        precondition(!IslandPageDeck().opensOnClick, "with no page a click still runs the pill's own tap")
        precondition(IslandPageDeck().opens(glance: false), "a bare island opens Home with no page (#884)")
        precondition(!IslandPageDeck().opens(glance: true), "with no page a meeting glance keeps its expansion")
        var status = IslandPageDeck()
        status.show(IslandNotice(id: "hover.timer", symbol: "timer", text: "Timer"), tappable: false)
        precondition(!status.opens(glance: false), "with no page a notice or status keeps the pill's long form")
        var three = deck(page("agents", order: 0), page("player", order: 10), page("day", order: 30))
        precondition(three.opensOnClick, "with a page a bare click opens it, whatever the pill shows")
        precondition(three.opens(glance: true), "a page opens whatever the pill shows")
        let ready = IslandNotice(id: "update", symbol: "arrow.down.circle", text: "Update ready")
        three.show(ready, tappable: true)
        precondition(three.notice == IslandPageRow(id: IslandPageDeck.noticeID, symbol: "arrow.down.circle",
                                                  title: "Update ready"), "a tappable notice is a button row")
        three.open()
        precondition(three.selection == .home && three.notice != nil, "the click opens Home with the notice on it")
        three.select(.page("day"))
        three.move(by: -1)
        precondition(three.notice?.title == "Update ready", "it heads every tab, so no page hides it")
        three.show(IslandNotice(id: "copied", symbol: nil, text: "Copied"), tappable: false)
        precondition(three.notice?.id == nil && three.notice?.title == "Copied", "a notice with no tap is a plain row")
        three.show(nil, tappable: false)
        precondition(three.notice == nil, "an ended notice leaves the page")
        var one = deck(page("player", order: 10))
        one.show(ready, tappable: true)
        one.open()
        precondition(one.current?.id == "player" && one.notice != nil, "a lone page carries it too")
    }

    static func focus() {
        var focus = IslandPageFocus()
        precondition(!focus.takesKey(pinned: false), "a hover open takes no key")
        precondition(focus.takesKey(pinned: true), "the pin's start keys the panel")
        precondition(!focus.takesKey(pinned: true), "a repost while pinned leaves the keyboard where it is")
        precondition(!focus.takesKey(pinned: false) && focus.takesKey(pinned: true), "a new pin keys it again")
    }

    static func sizing() {
        let rest = CGSize(width: 96, height: 24)
        let bare = IslandPageDeck.outline(content: CGSize(width: 300.2, height: 120.4), rest: rest, notch: nil,
                                          radius: 26, maxHeight: 800)
        precondition(bare == CGSize(width: 301, height: 121), "each page takes its own size, in whole points")
        let other = IslandPageDeck.outline(content: CGSize(width: 420, height: 90), rest: rest, notch: nil,
                                           radius: 26, maxHeight: 800)
        precondition(other != bare, "pages differ in width and height; no fixed size")
        precondition(IslandPageDeck.outline(content: CGSize(width: 40, height: 10), rest: rest, notch: nil, radius: 26,
                                            maxHeight: 800) == rest, "never smaller than the rest pill")
        let notched = IslandPageDeck.outline(content: CGSize(width: 150, height: 80), rest: rest, notch: 185,
                                             radius: 26, maxHeight: 800)
        precondition(notched.width == 237, "past a notch by one outline radius a side, as the headline")
        precondition(IslandPageDeck.outline(content: CGSize(width: 300, height: 2000), rest: rest, notch: nil,
                                            radius: 26, maxHeight: 700).height == 700, "never past the screen")
    }

    static func swipe() {
        /// One trackpad event `at` seconds in; a phase of nil is a device that sends none.
        func drag(_ swipe: inout IslandPageSwipe, _ deltaX: Double, deltaY: Double = 0, at: TimeInterval,
                  began: Bool = false, ended: Bool = false, momentum: Bool = false, hasPhase: Bool = true) -> Int {
            swipe.steps(deltaX: deltaX, deltaY: deltaY, timestamp: at, precise: true, hasPhase: hasPhase,
                        began: began, ended: ended, momentum: momentum)
        }
        let first = IslandPageSwipe.firstStep, tab = IslandPageSwipe.tabStep
        var swipe = IslandPageSwipe()
        precondition(drag(&swipe, -first / 2, at: 0, began: true) == 0, "a short swipe turns nothing")
        precondition(drag(&swipe, -first / 2, at: 0.01) == 1, "fingers moving left: next tab")
        precondition(drag(&swipe, -tab / 2, at: 0.02) == 0, "the same drag needs a tab's width for the next")
        precondition(drag(&swipe, -tab / 2, at: 0.03) == 1, "and then turns one more")
        precondition(drag(&swipe, first, at: 0.04) == -1, "turning back answers after the short first step")
        precondition(drag(&swipe, 0, at: 0.05, ended: true) == 0, "lifting the fingers ends the gesture")
        precondition(drag(&swipe, -tab * 3, at: 0.06, momentum: true) == 0, "momentum after the lift turns nothing")
        precondition(drag(&swipe, first, at: 1, began: true) == -1, "a new gesture right: previous")
        var vertical = IslandPageSwipe()
        precondition(drag(&vertical, -first * 3, deltaY: -first * 4, at: 0, began: true) == 0,
                     "a mostly vertical scroll is not a swipe")
        var loose = IslandPageSwipe()
        precondition(drag(&loose, -first / 2, at: 0, hasPhase: false) == 0, "without phases, half a step")
        precondition(drag(&loose, -first / 2, at: 1, hasPhase: false) == 0, "does not add up across a pause")
        var wheel = IslandPageSwipe()
        precondition(wheel.steps(deltaX: -1, deltaY: 0, timestamp: 0, precise: false, hasPhase: false, began: false,
                                 ended: false, momentum: false) == 1, "a sideways wheel notch turns one tab")
        precondition(wheel.steps(deltaX: 0, deltaY: -3, timestamp: 0, precise: false, hasPhase: false, began: false,
                                 ended: false, momentum: false) == 0, "an ordinary wheel notch turns nothing")
        precondition(wheel.steps(deltaX: .nan, deltaY: 0, timestamp: 0, precise: true, hasPhase: true, began: true,
                                 ended: false, momentum: false) == 0, "a broken delta is ignored")
    }

    static func keys() {
        typealias Key = IslandPageKey
        precondition(Key(keyCode: Key.leftArrow, characters: "", command: false) == .move(-1), "left arrow")
        precondition(Key(keyCode: Key.rightArrow, characters: "", command: false) == .move(1), "right arrow")
        precondition(Key(keyCode: Key.escape, characters: "\u{1b}", command: false) == .close, "Escape closes")
        precondition(Key(keyCode: 18, characters: "1", command: false) == .number(1), "1 picks the first tab")
        precondition(Key(keyCode: 29, characters: "0", command: false) == nil, "0 is not a tab")
        precondition(Key(keyCode: 15, characters: "r", command: true) == .refresh, "Command-R refreshes")
        precondition(Key(keyCode: 35, characters: "p", command: true) == .pin, "Command-P pins")
        precondition(Key(keyCode: 15, characters: "r", command: false) == nil, "a bare R is left alone")
        precondition(Key(keyCode: 18, characters: "1", command: true) == nil, "Command-1 is left alone")
    }

    static func player() {
        let start = Date(timeIntervalSince1970: 1_000)
        let time = IslandMediaTime(elapsed: 30, duration: 200, rate: 1, sampledAt: start)
        precondition(time.elapsed(at: start.addingTimeInterval(10)) == 40, "the time runs on from its sample")
        precondition(time.elapsed(at: start.addingTimeInterval(500)) == 200, "and stops at the end")
        precondition(IslandMediaTime(elapsed: 30, duration: 200, rate: 0, sampledAt: start)
            .elapsed(at: start.addingTimeInterval(60)) == 30, "paused, it holds")
        precondition(time.fraction(at: start.addingTimeInterval(70)) == 0.5, "the bar is the elapsed share")
        precondition(IslandMediaTime(elapsed: 3, duration: 0, rate: 1, sampledAt: start).fraction(at: start) == 0,
                     "an unknown length draws an empty bar")
        let playing = IslandNowPlaying(title: "Paper Lanterns", artist: "Juno Vale", artwork: nil, time: time,
                                       isPlaying: true)
        let page = IslandPlayerPage.page(playing)
        precondition(page.id == IslandPlayerPage.id && page.order < 20 && page.order > 0, "between Agents and System")
        guard case .media(let media)? = page.blocks.first else { preconditionFailure("the Player page is media") }
        precondition(media.title == "Paper Lanterns" && media.subtitle == "Juno Vale" && media.time == time,
                     "artwork, title, artist and time")
        precondition(media.buttons.map(\.symbol) == ["backward.fill", "pause.fill", "forward.fill"], "transport")
        precondition(page.line.text == "Paper Lanterns"
                     && page.line.buttons.map(\.symbol) == ["pause.fill", "forward.fill"],
                     "Home shows the song with its buttons")
        var paused = playing
        paused.isPlaying = false
        guard case .media(let still)? = IslandPlayerPage.page(paused).blocks.first else { preconditionFailure("media") }
        precondition(still.buttons[1].symbol == "play.fill", "paused, the middle button plays")
        precondition(Set(media.buttons.map(\.label)).count == 3, "each button is named for VoiceOver")
        let ids = media.buttons.map(\.id)
        precondition(ids.compactMap(IslandPlayerControl.init(rawValue:)) == [.previous, .playPause, .next],
                     "each button maps to a control")
        precondition(IslandPlayerControl(rawValue: IslandPage.refreshAction) == .refresh,
                     "Command-R reaches the player")
        var two = IslandPageDeck()
        two.set(page, id: IslandPlayerPage.id)
        two.set(IslandPage(id: "agents", title: "Agents", symbol: "person.2", order: 0, badge: 1,
                           line: IslandPageLine(text: "1 waiting"), blocks: []), id: "agents")
        precondition(two.homeLines.map(\.id) == ["agents", "player"], "agents waiting come before the player")
    }

    /// The card blocks (#1128): fixed slots, a hollow card half a slot, the row four across.
    static func cards() {
        typealias Card = IslandCardSlots.Card
        let gap: CGFloat = 8
        precondition(IslandCardSlots.count(groups: 1) == 3 && IslandCardSlots.count(groups: 4) == 4,
                     "a column keeps a third of the width with one machine, and narrows past three")
        precondition(IslandCardSlots.columnWidth(width: 736, columns: 3, gap: gap) == 240, "three columns share the width")
        let cards = [Card(column: 0, hollow: false, natural: 150), Card(column: 0, hollow: false, natural: 120),
                     Card(column: 1, hollow: false, natural: 130), Card(column: 1, hollow: true, natural: 60),
                     Card(column: 1, hollow: true, natural: 70), Card(column: 2, hollow: false, natural: 100)]
        precondition(IslandCardSlots.slot(cards, gap: gap) == 150, "a slot is the tallest full card")
        let frames = IslandCardSlots.columns(cards, width: 736, columns: 3, gap: gap)
        precondition(frames.map(\.height) == [150, 150, 150, 71, 71, 150],
                     "every full card fills a slot, a hollow half less the gap")
        precondition(frames[4].maxY == frames[1].maxY, "two hollow cards end level with a full card beside them")
        precondition(frames.map(\.minX) == [0, 0, 248, 248, 248, 496], "a card never leaves its column")
        precondition(frames[3].minY == 158 && frames[1].minY == 158, "the gap separates cards down a column")
        let spentOnly = [Card(column: 0, hollow: true, natural: 80)]
        precondition(IslandCardSlots.slot(spentOnly, gap: gap) == 168, "with only hollow cards, two fit one slot")
        precondition(IslandCardSlots.columns([Card(column: 5, hollow: false, natural: 10)], width: 736, columns: 3,
                                             gap: gap) == [.zero], "a column past the count draws nothing")
        let row = IslandCardSlots.row([90, 60, 120, 80, 70], width: 736, gap: gap)
        precondition(row.prefix(4).allSatisfy { $0.height == 120 && $0.minY == 0 }, "a row's cards share the tallest height")
        precondition(row[4].minX == 0 && row[4].minY == 128, "a fifth card wraps under the first")
        precondition(row[1].width == 178, "four across")
        let page = IslandPage(id: "agents", title: "Agents", symbol: "gauge.with.needle", order: 0,
            line: IslandPageLine(text: "C4 · Weekly runs out in 1 d 17 h"),
            blocks: [.columns([IslandCardGroup(title: "MBA", cards: [IslandCard(
                title: "C1", tag: IslandCardTag(symbol: "arrow.counterclockwise", text: "1 reset credit"),
                body: .meters([IslandCardMeter(label: "Weekly", value: "55% left", trailing: "in 5 d 14 h", fraction: 0.55,
                                               tick: 0.8, thick: true, warning: true, note: "Runs out in 1 d 17 h")]))])]),
                     .cards(IslandCardGroup(title: "Other", cards: [IslandCard(
                         title: "Codex", hollow: true,
                         body: .notice(symbol: "hourglass", headline: "Back in 2 d 19 h", detail: "Weekly limit used up"))]))])
        var deck = IslandPageDeck()
        deck.set(page, id: "agents")
        precondition(deck.current == page, "a page of cards posts like any other")
    }
}
