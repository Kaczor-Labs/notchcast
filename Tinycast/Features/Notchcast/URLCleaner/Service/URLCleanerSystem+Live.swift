// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's URL cleaner pasteboard read and rewrite.

import AppKit
import UniformTypeIdentifiers

extension URLCleanerSystem {
    static let live = URLCleanerSystem(
        observe: { ClipboardManager.willCapture = $0 },
        itemTypes: { NSPasteboard.general.pasteboardItems?.map { $0.types.map(\.rawValue) } ?? [] },
        isDeclared: { UTType($0)?.isDeclared == true },
        // Some "copy link" commands put the link on the pasteboard only as a URL.
        text: { NSPasteboard.general.string(forType: .string) ?? NSPasteboard.general.string(forType: .URL) },
        replace: { link in
            let board = NSPasteboard.general
            let hadURL = board.types?.contains(.URL) == true
            board.clearContents()
            board.setString(link, forType: .string)
            if hadURL { board.setString(link, forType: .URL) }
            board.setData(Data(), forType: ClipboardManager.internalType)
        }
    )
}
