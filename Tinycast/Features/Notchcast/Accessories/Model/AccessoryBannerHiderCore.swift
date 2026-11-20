// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchNotificationReaderCore: read budgets, stack cards and confirmed moves.

import Foundation

/// The hider's Accessibility calls; a failed read throws, so a partial tree never decides anything.
protocol AccessoryBannerAccess {
    associatedtype Element
    func windows() throws -> [Element]
    /// The open center keeps its banners in the same window as its list.
    func centerIsOpen() throws -> Bool
    func string(_ element: Element, _ attribute: String) throws -> String?
    func children(_ element: Element) throws -> [Element]
    /// Nil once the window is gone.
    func frame(_ element: Element) throws -> CGRect?
    func move(_ element: Element, to origin: CGPoint) -> Bool
    func same(_ lhs: Element, _ rhs: Element) -> Bool
    /// Every active display together, `.null` when unknown.
    func screens() -> CGRect
}

/// One card of a banner or a banner stack, as a complete read found it.
struct AccessoryBannerCard: Equatable, Sendable {
    var texts: [String]
    var transient: Bool
}

/// Hides the center's windows that only name our accessories; a moved one is listed until seen back or gone.
final class AccessoryBannerHiderCore<Access: AccessoryBannerAccess> {
    /// A window moved the moment the center made it waits this long for its banner to lay out.
    static var grace: TimeInterval { 0.6 }
    /// A move back that could not be confirmed is tried again this soon, with no Accessibility event.
    static var retry: TimeInterval { 0.2 }
    static var bannerRoles: Set<String> { ["AXNotificationCenterAlert", "AXNotificationCenterBanner"] }
    static var stackRoles: Set<String> { ["AXNotificationCenterAlertStack", "AXNotificationCenterBannerStack"] }

    private struct Record {
        let window: Access.Element
        let origin: CGPoint
        let since: Date
        var kept: Bool
        /// Moved, but not yet confirmed off screen, or on its way back.
        var restoring: Bool
    }

    private enum Placement { case onScreen, offScreen, gone, unknown }

    private let access: Access
    private let now: () -> Date
    private var records: [Record] = []
    private var deadline = Date.distantPast
    private var remaining = 0
    private var incomplete = false

    init(access: Access, now: @escaping () -> Date) {
        self.access = access
        self.now = now
    }

    var hidesWindows: Bool { !records.isEmpty }

    /// When a pass must run again without an Accessibility event: a move back to retry, or a grace to end.
    var nextPass: Date? {
        if records.contains(where: \.restoring) { return now().addingTimeInterval(Self.retry) }
        return records.filter { !$0.kept }.map { $0.since.addingTimeInterval(Self.grace) }.min()
    }

    /// A window the center just made goes out of sight before its banner draws; `scan` decides if it stays.
    func prehide(_ window: Access.Element) {
        beginRead()
        guard fetch({ try access.centerIsOpen() }) == false else { return }
        _ = hide(window, kept: false)
    }

    /// Keeps away each window whose banners all name a live accessory; a partial pass hides nothing new.
    func scan(names: [String: Date]) {
        for record in records where record.restoring { show(record.window) }
        beginRead()
        guard let open = fetch({ try access.centerIsOpen() }), !open else { return restoreAll() }
        guard let windows = fetch({ try access.windows() }) else { return }
        if windows.count > 32 { incomplete = true }
        var read: [(window: Access.Element, cards: [AccessoryBannerCard])] = []
        for window in windows where usable {
            var cards: [AccessoryBannerCard] = []
            findBanners(window, depth: 0, into: &cards)
            read.append((window, cards))
        }
        let complete = usable
        let time = now()
        for (window, cards) in read {
            let index = records.firstIndex { access.same($0.window, window) }
            if complete, AccessoryPolicy.hides(cards: cards, names: names, now: time) {
                if let index { records[index].kept = true } else { _ = hide(window, kept: true) }
                continue
            }
            guard let index, !records[index].restoring else { continue }
            let graceOver = time.timeIntervalSince(records[index].since) >= Self.grace
            let judged = complete && (records[index].kept || !cards.isEmpty)
            if judged || (!records[index].kept && graceOver) { show(window) }
        }
        guard complete else { return }
        for record in records where !windows.contains(where: { access.same($0, record.window) }) {
            show(record.window)
        }
    }

    /// Puts back every window this hider moved; one it cannot confirm stays listed for the next try.
    func restoreAll() {
        for record in records { show(record.window) }
    }

    private func hide(_ window: Access.Element, kept: Bool) -> Bool {
        let screens = access.screens()
        guard !screens.isNull, let read = frame(of: window), let frame = read, frame.intersects(screens),
              !records.contains(where: { access.same($0.window, window) }) else { return false }
        let away = CGPoint(x: screens.minX - frame.width - 1_000, y: screens.minY - frame.height - 1_000)
        guard access.move(window, to: away) else { return false }
        // The move happened: keep its origin before any read that may fail, so the window is never lost.
        records.append(Record(window: window, origin: frame.origin, since: now(), kept: kept, restoring: true))
        guard placement(of: window) == .offScreen else {
            _ = access.move(window, to: frame.origin)
            if [.onScreen, .gone].contains(placement(of: window)) { records.removeAll { access.same($0.window, window) } }
            return false
        }
        records[records.count - 1].restoring = false
        return true
    }

    @discardableResult
    private func show(_ window: Access.Element) -> Bool {
        guard let index = records.firstIndex(where: { access.same($0.window, window) }) else { return true }
        records[index].restoring = true
        switch placement(of: window) {
        case .unknown: return false
        case .offScreen:
            guard access.move(window, to: records[index].origin),
                  [.onScreen, .gone].contains(placement(of: window)) else { return false }
        case .onScreen, .gone: break
        }
        records.removeAll { access.same($0.window, window) }
        return true
    }

    /// Read outside the pass budget, so putting a window back never waits on it.
    private func placement(of window: Access.Element) -> Placement {
        let screens = access.screens()
        guard !screens.isNull, let read = frame(of: window) else { return .unknown }
        guard let frame = read else { return .gone }
        return frame.intersects(screens) ? .onScreen : .offScreen
    }

    /// Nil when the read failed, `.some(nil)` once the window is gone.
    private func frame(of window: Access.Element) -> CGRect?? {
        do { return .some(try access.frame(window)) } catch { return nil }
    }

    private var usable: Bool { !incomplete && remaining > 0 && now() < deadline }

    private func beginRead() {
        deadline = now().addingTimeInterval(0.8)
        remaining = 384
        incomplete = false
    }

    private func fetch<Value>(_ body: () throws -> Value) -> Value? {
        guard usable else { return nil }
        do {
            let value = try body()
            return usable ? value : nil
        } catch {
            incomplete = true
            return nil
        }
    }

    private func visit(depth: Int) -> Bool {
        guard usable else { return false }
        guard depth <= 10 else {
            incomplete = true
            return false
        }
        remaining -= 1
        return usable
    }

    private func findBanners(_ node: Access.Element, depth: Int, into cards: inout [AccessoryBannerCard]) {
        guard visit(depth: depth) else { return }
        let subrole = string(node, "AXSubrole") ?? ""
        if Self.bannerRoles.contains(subrole) {
            cards.append(AccessoryBannerCard(texts: message(node) ?? [], transient: subrole == "AXNotificationCenterBanner"))
        } else if Self.stackRoles.contains(subrole) {
            findCards(node, depth: depth, transient: subrole == "AXNotificationCenterBannerStack", into: &cards)
        } else {
            for child in children(node) { findBanners(child, depth: depth + 1, into: &cards) }
        }
    }

    /// Each card of a stack alone; a wrapper holding one whole card is descended, never counted twice.
    private func findCards(_ node: Access.Element, depth: Int, transient: Bool, into cards: inout [AccessoryBannerCard]) {
        guard usable else { return }
        let own = message(node)
        let next = own == nil ? children(node) : children(node).filter { message($0) == own }
        if let own, next.isEmpty { return cards.append(AccessoryBannerCard(texts: own, transient: transient)) }
        for child in next {
            guard visit(depth: depth + 1) else { return }
            findCards(child, depth: depth + 1, transient: transient, into: &cards)
        }
    }

    /// The texts of exactly one message, nil for none or several; only labelled static texts, never controls.
    private func message(_ root: Access.Element) -> [String]? {
        var texts: [(identifier: String, value: String)] = []
        walk(root, depth: 0) { node in
            guard string(node, "AXRole") == "AXStaticText" else { return }
            let identifier = string(node, "AXIdentifier") ?? ""
            guard ["", "header", "title", "subtitle", "body"].contains(identifier),
                  let text = string(node, "AXValue"), !text.isEmpty else { return }
            texts.append((identifier, text))
        }
        guard usable else { return nil }
        if texts.allSatisfy({ $0.identifier.isEmpty }) { return (2...3).contains(texts.count) ? texts.map(\.value) : nil }
        let count = { (identifier: String) in texts.filter { $0.identifier == identifier }.count }
        guard count("title") == 1, count("header") <= 1, count("subtitle") <= 1, count("body") <= 1,
              count("") == 0 else { return nil }
        return texts.map(\.value)
    }

    private func walk(_ node: Access.Element, depth: Int, _ action: (Access.Element) -> Void) {
        guard visit(depth: depth) else { return }
        action(node)
        for child in children(node) { walk(child, depth: depth + 1, action) }
    }

    private func children(_ node: Access.Element) -> [Access.Element] {
        guard let children = fetch({ try access.children(node) }) else { return [] }
        guard children.count <= 64 else {
            incomplete = true
            return []
        }
        return children
    }

    private func string(_ node: Access.Element, _ attribute: String) -> String? {
        fetch { try access.string(node, attribute) }.flatMap(\.self)
    }
}
