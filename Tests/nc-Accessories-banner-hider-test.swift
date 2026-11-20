// notchcast-sources: Tinycast/Features/Notchcast/Accessories/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift

import Foundation

/// Notification Center as the hider reads it: a tree of numbered nodes, window frames and a clock.
final class FakeCenter: AccessoryBannerAccess {
    struct Failure: Error {}

    var windowList: [Int] = []
    var open = false
    var tree: [Int: [Int]] = [:]
    var attributes: [Int: [String: String]] = [:]
    var frames: [Int: CGRect] = [:]
    /// Reads of these nodes time out.
    var failing: Set<Int> = []
    var failWindows = false
    var refuseMoves: Set<Int> = []
    var moves: [(window: Int, to: CGPoint)] = []
    var now = Date(timeIntervalSinceReferenceDate: 0)
    let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private var next = 100

    func windows() throws -> [Int] {
        if failWindows { throw Failure() }
        return windowList
    }

    func centerIsOpen() throws -> Bool { open }

    func string(_ element: Int, _ attribute: String) throws -> String? {
        if failing.contains(element) { throw Failure() }
        return attributes[element]?[attribute]
    }

    func children(_ element: Int) throws -> [Int] {
        if failing.contains(element) { throw Failure() }
        return tree[element] ?? []
    }

    func frame(_ element: Int) throws -> CGRect? {
        if failing.contains(element) { throw Failure() }
        return frames[element]
    }

    func move(_ element: Int, to origin: CGPoint) -> Bool {
        guard !refuseMoves.contains(element), frames[element] != nil else { return false }
        moves.append((element, origin))
        frames[element]?.origin = origin
        return true
    }

    func same(_ lhs: Int, _ rhs: Int) -> Bool { lhs == rhs }
    func screens() -> CGRect { screen }

    func node(_ attributes: [String: String], _ children: [Int] = []) -> Int {
        next += 1
        self.attributes[next] = attributes
        tree[next] = children
        return next
    }

    func text(_ value: String, _ identifier: String = "title") -> Int {
        node(["AXRole": "AXStaticText", "AXIdentifier": identifier, "AXValue": value])
    }

    /// One message: a title and an optional body.
    func banner(_ title: String, _ body: String? = nil, role: String = "AXNotificationCenterBanner") -> Int {
        node(["AXSubrole": role], [text(title)] + (body.map { [text($0, "body")] } ?? []))
    }

    /// A new on-screen window holding `content`.
    func window(_ content: [Int]) -> Int {
        let window = node(["AXRole": "AXWindow"], content)
        frames[window] = CGRect(x: 700, y: 40, width: 300, height: 100)
        windowList.append(window)
        return window
    }

    func shown(_ window: Int) -> Bool { frames[window].map(screen.intersects) ?? false }
}

@main
enum AccessoryBannerHiderTests {
    static let names = ["kim's airpods pro": Date(timeIntervalSinceReferenceDate: 10)]

    static func main() {
        matching()
        hidesOnlyOurs()
        stacks()
        partialReads()
        failedReads()
        movesBack()
        prehideGrace()
        print("PASS nc-Accessories-banner-hider-test")
    }

    static func make(_ center: FakeCenter) -> AccessoryBannerHiderCore<FakeCenter> {
        AccessoryBannerHiderCore(access: center, now: { center.now })
    }

    static func matching() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let card = { (texts: [String]) in AccessoryBannerCard(texts: texts, transient: true) }
        precondition(AccessoryPolicy.hides(cards: [card(["Kim's AirPods Pro", "Connected"])], names: names, now: now),
                     "macOS's banner for the accessory we just announced")
        precondition(!AccessoryPolicy.hides(cards: [card(["Kim's AirPods Pro"])], names: names,
                                            now: now.addingTimeInterval(10)), "not once its window has passed")
        precondition(!AccessoryPolicy.hides(cards: [card(["Messages", "See you at 5"])], names: names, now: now),
                     "never another app's banner")
        precondition(!AccessoryPolicy.hides(cards: [], names: names, now: now), "no card, nothing to hide")
        precondition(!AccessoryPolicy.hides(cards: [AccessoryBannerCard(texts: ["Kim's AirPods Pro"], transient: false)],
                                            names: names, now: now), "a persistent alert stays")
        let short = ["pro": Date.distantFuture]
        precondition(!AccessoryPolicy.hides(cards: [card(["Pro tip: save often"])], names: short, now: now),
                     "a name under 4 letters matches nothing")
        let mouse = ["mouse": Date.distantFuture]
        precondition(!AccessoryPolicy.hides(cards: [card(["Mousetrap sale"])], names: mouse, now: now), "whole words only")
        precondition(AccessoryPolicy.hides(cards: [card(["Mouse: battery low"])], names: mouse, now: now),
                     "a name followed by punctuation")
        precondition(!AccessoryPolicy.hides(cards: [card(["Kim's AirPods", "Pro Max deals"])], names: names, now: now),
                     "one text holds the whole name, never two joined")
        precondition(AccessoryPolicy.hides(cards: [card(["Kim's AirPods Pro"]), card(["Kim's AirPods Pro", "Case"])],
                                           names: names, now: now), "every card ours")
        precondition(!AccessoryPolicy.hides(cards: [card(["Kim's AirPods Pro"]), card(["Messages"])], names: names,
                                            now: now), "one other card keeps the window")
    }

    static func hidesOnlyOurs() {
        let center = FakeCenter()
        let hider = make(center)
        let ours = center.window([center.banner("Kim's AirPods Pro", "Connected")])
        let theirs = center.window([center.banner("Messages", "See you at 5")])
        let mixed = center.window([center.banner("Kim's AirPods Pro"), center.banner("Mail", "Invoice")])
        let alert = center.window([center.banner("Kim's AirPods Pro", role: "AXNotificationCenterAlert")])
        hider.scan(names: names)
        precondition(!center.shown(ours), "our banner's window goes")
        precondition(center.shown(theirs) && center.shown(mixed) && center.shown(alert), "every other stays")

        center.open = true
        hider.scan(names: names)
        precondition(center.shown(ours) && !hider.hidesWindows, "the open center brings it back at once")
        center.open = false
        hider.scan(names: names)
        precondition(!center.shown(ours), "closed again: hidden again")
        center.now = center.now.addingTimeInterval(11)
        hider.scan(names: names)
        precondition(center.shown(ours) && !hider.hidesWindows, "back once its name expires")

        center.now = Date(timeIntervalSinceReferenceDate: 0)
        hider.scan(names: names)
        center.windowList.removeAll { $0 == ours }
        center.frames[ours] = nil
        hider.scan(names: names)
        precondition(!hider.hidesWindows, "a window that is gone is forgotten")
    }

    static func stacks() {
        let center = FakeCenter()
        let hider = make(center)
        let card = center.node(["AXRole": "AXGroup"], [center.text("Kim's AirPods Pro"), center.text("Connected", "body")])
        let message = center.node(["AXRole": "AXGroup"], [center.text("Messages"), center.text("Running late", "body")])
        let stack = center.window([center.node(["AXSubrole": "AXNotificationCenterBannerStack"], [card, message])])
        hider.scan(names: names)
        precondition(center.shown(stack), "a stack is judged card by card: the message keeps it in sight")
        let joined = center.banner("Kim's AirPods Pro", "Connected")
        let extra = center.text("Messages")
        center.tree[joined]?.append(extra)
        let two = center.window([joined])
        hider.scan(names: names)
        precondition(center.shown(two), "a banner whose texts are two messages is not one card")

        let inner = center.node(["AXRole": "AXGroup"], [center.text("Kim's AirPods Pro")])
        let wrapped = center.node(["AXRole": "AXGroup"], [inner])
        let alone = center.window([center.node(["AXSubrole": "AXNotificationCenterBannerStack"], [wrapped])])
        hider.scan(names: names)
        precondition(!center.shown(alone), "a wrapper around one whole card is that card")
        let cardless = center.window([center.node(["AXSubrole": "AXNotificationCenterBannerStackFooter"],
                                                  [center.text("Kim's AirPods Pro")])])
        hider.scan(names: names)
        precondition(center.shown(cardless), "only the exact roles count, never a prefix")
    }

    static func partialReads() {
        let center = FakeCenter()
        let hider = make(center)
        let ours = center.banner("Kim's AirPods Pro")
        let other = center.banner("Messages")
        let window = center.window([ours, other])
        center.failing = [other]
        hider.scan(names: names)
        precondition(center.shown(window), "a timed-out read of one banner hides nothing")

        center.failing = []
        let crowded = center.window([center.node(["AXRole": "AXGroup"], (0..<65).map { _ in center.text("x") })])
        let alone = center.window([center.banner("Kim's AirPods Pro")])
        hider.scan(names: names)
        precondition(center.shown(alone) && center.shown(crowded), "a list past 64 children makes the pass partial")
        center.windowList.removeAll { $0 == crowded }

        var deep = center.banner("Kim's AirPods Pro")
        for _ in 0..<11 { deep = center.node(["AXRole": "AXGroup"], [deep]) }
        let buried = center.window([deep])
        hider.scan(names: names)
        precondition(center.shown(alone) && center.shown(buried), "past depth 10 the pass is partial")
        center.windowList.removeAll { $0 == buried }

        hider.scan(names: names)
        precondition(!center.shown(alone), "a complete pass hides it")
        let busy = center.window((0..<60).map { _ in center.node(["AXRole": "AXGroup"], (0..<7).map { _ in center.text("y") }) })
        hider.scan(names: names)
        precondition(!center.shown(alone), "a pass out of budget keeps what it hid")
        precondition(center.shown(busy), "and hides nothing new")
    }

    static func failedReads() {
        let center = FakeCenter()
        let hider = make(center)
        let ours = center.window([center.banner("Kim's AirPods Pro")])
        hider.scan(names: names)
        precondition(!center.shown(ours), "hidden")
        center.failWindows = true
        hider.scan(names: names)
        precondition(hider.hidesWindows && !center.shown(ours), "a failed window list keeps the record and the window")
        center.failWindows = false
        center.now = center.now.addingTimeInterval(11)
        hider.scan(names: names)
        precondition(center.shown(ours) && !hider.hidesWindows, "and the next pass puts it back")
    }

    static func movesBack() {
        let center = FakeCenter()
        let hider = make(center)
        let ours = center.window([center.banner("Kim's AirPods Pro")])
        hider.scan(names: names)
        center.refuseMoves = [ours]
        center.open = true
        hider.scan(names: names)
        precondition(!center.shown(ours) && hider.hidesWindows, "a refused move back keeps the record")
        precondition(hider.nextPass == center.now.addingTimeInterval(0.2), "and asks for a retry without an event")
        center.refuseMoves = []
        center.failing = [ours]
        hider.restoreAll()
        precondition(hider.hidesWindows, "a window it cannot read stays listed")
        center.failing = []
        hider.restoreAll()
        precondition(center.shown(ours) && !hider.hidesWindows && hider.nextPass == nil, "then comes back")
    }

    static func prehideGrace() {
        let center = FakeCenter()
        let hider = make(center)
        let fresh = center.window([])
        hider.prehide(fresh)
        precondition(!center.shown(fresh), "a new window goes before its banner draws")
        precondition(hider.nextPass == center.now.addingTimeInterval(0.6), "for its grace")
        hider.scan(names: names)
        precondition(!center.shown(fresh), "still empty inside the grace: still away")
        center.now = center.now.addingTimeInterval(0.6)
        hider.scan(names: names)
        precondition(center.shown(fresh), "empty after it: back")

        let theirs = center.window([])
        hider.prehide(theirs)
        center.tree[theirs] = [center.banner("Messages")]
        hider.scan(names: names)
        precondition(center.shown(theirs), "another app's banner comes back before the grace ends")

        let ours = center.window([])
        hider.prehide(ours)
        center.tree[ours] = [center.banner("Kim's AirPods Pro")]
        hider.scan(names: names)
        precondition(!center.shown(ours) && hider.nextPass == nil, "ours is kept, with no pass pending")

        center.open = true
        let listed = center.window([])
        hider.prehide(listed)
        precondition(center.shown(listed), "never while the center is open")
    }
}
