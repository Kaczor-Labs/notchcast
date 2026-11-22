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
        pressMatchStyle: { pressNativeMatchStyle() },
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

private let matchStyleTimeout: Float = 0.35

@MainActor
private let matchStyleMenu = MatchStyleMenu<AXUIElement>(
    prepare: { AXUIElementSetMessagingTimeout($0, matchStyleTimeout) },
    read: { element, attribute in
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (status, value)
    },
    performPress: { AXUIElementPerformAction($0, kAXPressAction as CFString) }
)

@MainActor
private func pressNativeMatchStyle() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication,
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
    let pid = app.processIdentifier
    return matchStyleMenu.press(pid: pid, bundleIdentifier: app.bundleIdentifier) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, matchStyleTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
