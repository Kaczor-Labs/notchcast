// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's menu press: a bounded menu-bar walk and AXPress, nothing drawn.

import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute names are constant C globals.
@preconcurrency import ApplicationServices

/// A Gecko browser's selected tabs: counted in its tab strip, copied by its own File › Share command.
nonisolated enum CopyPathTabLinks {
    /// The tab walk keeps the page read's budget: hundreds of tabs fit, a hung browser stops in 1 s.
    static let walkTimeout: Float = 1
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
        let app = AXUIElementCreateApplication(pid)
        guard let window = try element(app, kAXFocusedWindowAttribute, timeout: walkTimeout) else { return 0 }
        var queue = [window]
        var index = 0
        var selected = 0
        while index < queue.count, index < maxElements {
            let current = queue[index]
            index += 1
            let role = try string(current, kAXRoleAttribute, timeout: walkTimeout)
            if role == kAXRadioButtonRole as String,
                try string(current, kAXSubroleAttribute, timeout: walkTimeout) == "AXTabButton" {
                if try read(current, kAXValueAttribute, timeout: walkTimeout) as? Int == 1 { selected += 1 }
                continue
            }
            guard role != "AXWebArea" else { continue }
            queue += try children(current, timeout: walkTimeout)
        }
        return selected
    }

    /// Presses File › Share's first item with no menu opened, then waits for the browser's write.
    @concurrent
    static func browserCopy(pid: Int32) async throws -> CopyPathBrowserCopy? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        guard let share = try shareItem(pid: pid) else { return nil }
        let before = NSPasteboard.general.changeCount
        guard let press = try await copyLinksItem(share),
            AXUIElementPerformAction(press, kAXPressAction as CFString) == .success else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now + copyWait
        while NSPasteboard.general.changeCount == before {
            guard clock.now < deadline else { return nil }
            try await Task.sleep(for: copyPoll)
        }
        let changeCount = NSPasteboard.general.changeCount
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return CopyPathBrowserCopy(text: text, changeCount: changeCount)
    }

    /// The Share item, read fresh from the menu bar: by its ⌘S neighbour in any menu, else by title.
    private static func shareItem(pid: Int32) throws -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = try element(app, kAXMenuBarAttribute, timeout: menuTimeout) else { return nil }
        var menus: [[(AXUIElement, CopyPathMenuItem)]] = []
        for barItem in try children(bar, timeout: menuTimeout).prefix(maxMenus) {
            guard let menu = try children(barItem, timeout: menuTimeout).first else { continue }
            let items = try menuItems(menu)
            if let index = CopyPathShareMenu.shareByShortcut(items.map(\.1)) { return items[index].0 }
            menus.append(items)
        }
        for items in menus {
            if let index = CopyPathShareMenu.shareByTitle(items.map(\.1)) { return items[index].0 }
        }
        return nil
    }

    /// Share's first item once Gecko has filled it; each try reads Share's children anew.
    private static func copyLinksItem(_ share: AXUIElement) async throws -> AXUIElement? {
        for attempt in 0..<shareReads {
            if attempt > 0 { try await Task.sleep(for: shareRetry) }
            guard let menu = try children(share, timeout: menuTimeout).first else { continue }
            let items = try menuItems(menu)
            if let index = CopyPathShareMenu.copyLinks(items.map(\.1)) { return items[index].0 }
        }
        return nil
    }

    private static func menuItems(_ menu: AXUIElement) throws -> [(AXUIElement, CopyPathMenuItem)] {
        let names = [kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                     kAXEnabledAttribute, kAXChildrenAttribute] as CFArray
        return try children(menu, timeout: menuTimeout).map { item in
            try Task.checkCancellation()
            AXUIElementSetMessagingTimeout(item, menuTimeout)
            var raw: CFArray?
            let status = AXUIElementCopyMultipleAttributeValues(item, names, [], &raw)
            guard try CopyPathStatus.accessibility(status.rawValue), let values = raw as? [Any], values.count == 5
            else { return (item, CopyPathMenuItem(isEnabled: false)) }
            let submenu = (values[4] as? [AXUIElement])?.isEmpty == false
            return (item, CopyPathMenuItem(
                title: values[0] as? String, commandKey: values[1] as? String,
                modifiers: values[2] as? Int ?? 0, isEnabled: values[3] as? Bool ?? true, hasSubmenu: submenu))
        }
    }

    private static func children(_ element: AXUIElement, timeout: Float) throws -> [AXUIElement] {
        guard let value = try read(element, kAXChildrenAttribute, timeout: timeout),
            CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func element(_ element: AXUIElement, _ attribute: String, timeout: Float) throws -> AXUIElement? {
        guard let value = try read(element, attribute, timeout: timeout),
            CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String, timeout: Float) throws -> String? {
        try read(element, attribute, timeout: timeout) as? String
    }

    private static func read(_ element: AXUIElement, _ attribute: String, timeout: Float) throws -> CFTypeRef? {
        try Task.checkCancellation()
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return try CopyPathStatus.accessibility(status.rawValue) ? value : nil
    }
}
