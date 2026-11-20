// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's menu press: a bounded menu-bar walk and AXPress, nothing drawn.

import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute names are constant C globals.
@preconcurrency import ApplicationServices

/// A Gecko browser's selected tabs: counted in its tab strip, copied by its own File › Share command.
nonisolated enum CopyPathTabLinks {
    private typealias AX = CopyPathAccessibility

    /// Each walk's whole budget; no read outlives it, so a hung browser costs at most this per walk.
    static let walkBudget = Duration.seconds(1)
    static let maxElements = 2000
    /// A busy browser must not hold the menu walk; every menu element gets the same short leash.
    static let menuTimeout: Float = 0.35
    static let maxMenus = 24
    /// Gecko fills Share's items a moment after the selection changes, so its children are re-read.
    static let shareReads = 6
    static let shareRetry = Duration.milliseconds(25)
    static let copyWait = Duration.seconds(1)
    static let copyPoll = Duration.milliseconds(5)

    @concurrent
    static func selectedTabs(pid: Int32) async throws -> Int {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let deadline = ContinuousClock.now + walkBudget
        let app = AXUIElementCreateApplication(pid)
        func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
            try AX.leashed(deadline, cap: 1) { try AX.read(element, attribute, timeout: $0) }
        }
        do {
            guard let window = try AX.leashed(deadline, cap: 1, {
                try AX.element(app, kAXFocusedWindowAttribute, timeout: $0)
            }) else { return 0 }
            var queue = [window]
            var index = 0
            var selected = 0
            while index < queue.count, index < maxElements {
                let current = queue[index]
                index += 1
                let role = try value(current, kAXRoleAttribute) as? String
                if role == kAXRadioButtonRole as String,
                    try value(current, kAXSubroleAttribute) as? String == "AXTabButton" {
                    if try value(current, kAXValueAttribute) as? Int == 1 { selected += 1 }
                    continue
                }
                guard role != "AXWebArea" else { continue }
                queue += try AX.leashed(deadline, cap: 1) { try AX.children(current, timeout: $0) }
            }
            return selected
        } catch is AX.BudgetSpent {
            return 0
        }
    }

    /// Presses File › Share's first item with no menu opened, then waits for the browser's write.
    @concurrent
    static func browserCopy(pid: Int32) async throws -> String? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let deadline = ContinuousClock.now + walkBudget
        guard let share = try shareItem(pid: pid, deadline: deadline) else { return nil }
        let before = NSPasteboard.general.changeCount
        guard let press = try await copyLinksItem(share, deadline: deadline),
            AXUIElementPerformAction(press, kAXPressAction as CFString) == .success else { return nil }
        let clock = ContinuousClock()
        let copyDeadline = clock.now + copyWait
        while clock.now < copyDeadline {
            // The count moves on the browser's clear, a moment before its text is there.
            if NSPasteboard.general.changeCount != before, let text = NSPasteboard.general.string(forType: .string) {
                return text
            }
            try await Task.sleep(for: copyPoll)
        }
        return nil
    }

    /// The Share item, read fresh from the menu bar: by its ⌘S neighbour in any menu, else by title.
    private static func shareItem(pid: Int32, deadline: ContinuousClock.Instant) throws -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let timeout = AX.leash(deadline, cap: menuTimeout),
            let bar = try AX.element(app, kAXMenuBarAttribute, timeout: timeout),
            let timeout = AX.leash(deadline, cap: menuTimeout) else { return nil }
        var menus: [[(AXUIElement, CopyPathMenuItem)]] = []
        for barItem in try AX.children(bar, timeout: timeout).prefix(maxMenus) {
            guard let timeout = AX.leash(deadline, cap: menuTimeout) else { return nil }
            guard let menu = try AX.children(barItem, timeout: timeout).first else { continue }
            guard let items = try menuItems(menu, deadline: deadline) else { return nil }
            if let index = CopyPathShareMenu.shareByShortcut(items.map(\.1)) { return items[index].0 }
            menus.append(items)
        }
        for items in menus {
            if let index = CopyPathShareMenu.shareByTitle(items.map(\.1)) { return items[index].0 }
        }
        return nil
    }

    /// Share's first item once Gecko has filled it; each try reads Share's children anew.
    private static func copyLinksItem(
        _ share: AXUIElement, deadline: ContinuousClock.Instant
    ) async throws -> AXUIElement? {
        for attempt in 0..<shareReads {
            if attempt > 0 { try await Task.sleep(for: shareRetry) }
            guard let timeout = AX.leash(deadline, cap: menuTimeout) else { return nil }
            guard let menu = try AX.children(share, timeout: timeout).first else { continue }
            guard let items = try menuItems(menu, deadline: deadline) else { return nil }
            if let index = CopyPathShareMenu.copyLinks(items.map(\.1)) { return items[index].0 }
        }
        return nil
    }

    /// One menu's items; nil once the walk's deadline has passed.
    private static func menuItems(
        _ menu: AXUIElement, deadline: ContinuousClock.Instant
    ) throws -> [(AXUIElement, CopyPathMenuItem)]? {
        let names = [kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                     kAXEnabledAttribute, kAXChildrenAttribute] as CFArray
        guard let timeout = AX.leash(deadline, cap: menuTimeout) else { return nil }
        var items: [(AXUIElement, CopyPathMenuItem)] = []
        for item in try AX.children(menu, timeout: timeout) {
            try Task.checkCancellation()
            guard let timeout = AX.leash(deadline, cap: menuTimeout) else { return nil }
            AXUIElementSetMessagingTimeout(item, timeout)
            var raw: CFArray?
            let status = AXUIElementCopyMultipleAttributeValues(item, names, [], &raw)
            guard try CopyPathStatus.accessibility(status.rawValue), let values = raw as? [Any], values.count == 5 else {
                items.append((item, CopyPathMenuItem(isEnabled: false)))
                continue
            }
            let submenu = (values[4] as? [AXUIElement])?.isEmpty == false
            items.append((item, CopyPathMenuItem(
                title: values[0] as? String, commandKey: values[1] as? String,
                modifiers: values[2] as? Int ?? 0, isEnabled: values[3] as? Bool ?? false, hasSubmenu: submenu)))
        }
        return items
    }
}
