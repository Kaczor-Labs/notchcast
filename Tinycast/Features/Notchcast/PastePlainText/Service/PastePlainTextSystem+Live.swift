// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's paste plain service and transient paste: the held keys and the menu.

import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute names are constant C globals.
@preconcurrency import ApplicationServices

extension Task: PlainPasteTimer where Success == Void, Failure == Never {}

extension PastePlainTextSystem {
    static let live = PastePlainTextSystem(
        makeBoard: { GeneralPlainPasteBoard() },
        postCommandV: { Paster.postCommandV() },
        modifiersHeld: {
            !CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl]).isEmpty
        },
        pressMatchStyle: { MatchStyleMenu.press() },
        now: { .now },
        after: { delay, work in
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                work()
            }
        }
    )
}

@MainActor
private final class GeneralPlainPasteBoard: PlainPasteBoard {
    private let board = NSPasteboard.general

    var changeCount: Int { board.changeCount }
    var types: [String] { board.types?.map(\.rawValue) ?? [] }
    var string: String? { board.string(forType: .string) }
    var ownMarker: String { ClipboardManager.internalType.rawValue }

    func rtfText() -> String? {
        board.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string }
    }

    func rtfdText() -> String? {
        board.data(forType: .rtfd).flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil)?.string }
    }

    func htmlText() -> String? {
        board.data(forType: .html).flatMap { NSAttributedString(html: $0, documentAttributes: nil)?.string }
    }

    var itemTypes: [[String]] { (board.pasteboardItems ?? []).map { $0.types.map(\.rawValue) } }

    func data(item: Int, type: String) -> Data? {
        guard let items = board.pasteboardItems, items.indices.contains(item) else { return nil }
        return items[item].data(forType: .init(type))
    }

    func write(_ items: [[PlainPasteEntry]], ifChangeCount changeCount: Int) -> PlainPasteWrite {
        var copies: [NSPasteboardItem] = []
        for entries in items {
            let copy = NSPasteboardItem()
            for entry in entries {
                guard copy.setData(entry.data, forType: .init(entry.type)) else {
                    return board.changeCount == changeCount ? .failed(changeCount: changeCount) : .superseded
                }
            }
            copies.append(copy)
        }
        guard board.changeCount == changeCount else { return .superseded }
        board.clearContents()
        guard copies.isEmpty || board.writeObjects(copies) else { return .failed(changeCount: board.changeCount) }
        return .written(changeCount: board.changeCount)
    }
}

/// The front app's own matching-style paste, found by key equivalent and never by localized title.
@MainActor
private enum MatchStyleMenu {
    /// A busy app must not hold the main actor for AX's default multi-second timeout.
    private static let timeout: Float = 0.35
    /// A direct item of a top-level menu: bar, bar item, menu, item.
    private static let maxDepth = 3
    private static let maxVisited = 600

    /// Processes with no such item, so their menus are not walked on every press; a disabled one retries.
    private static var withoutItem: Set<pid_t> = []

    static func press() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            !withoutItem.contains(app.processIdentifier) else { return false }
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let menuBar = element(application, kAXMenuBarAttribute) else { return false }
        var visited = 0
        guard let item = find(in: menuBar, app: app.bundleIdentifier, depth: 0, visited: &visited) else {
            if withoutItem.count >= 64 { withoutItem.removeAll() }
            withoutItem.insert(pid)
            return false
        }
        guard (read(item, kAXEnabledAttribute) as? NSNumber)?.boolValue != false else { return false }
        // cannotComplete is a timed-out press that may still paste; a fallback would paste twice.
        return [.success, .cannotComplete].contains(AXUIElementPerformAction(item, kAXPressAction as CFString))
    }

    private static func find(in element: AXUIElement, app: String?, depth: Int, visited: inout Int) -> AXUIElement? {
        guard depth <= maxDepth, visited < maxVisited else { return nil }
        visited += 1
        AXUIElementSetMessagingTimeout(element, timeout)
        if PlainPastePolicy.isMatchStyleEquivalent(
            bundleIdentifier: app, commandCharacter: read(element, kAXMenuItemCmdCharAttribute) as? String,
            modifierMask: (read(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.uint32Value,
            isEnabled: true) {
            return element
        }
        guard depth < maxDepth else { return nil }
        for child in read(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let match = find(in: child, app: app, depth: depth + 1, visited: &visited) { return match }
        }
        return nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = read(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
