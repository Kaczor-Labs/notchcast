// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's URL cleaner pasteboard read and rewrite.

import AppKit
import UniformTypeIdentifiers

extension URLCleanerSystem {
    @MainActor
    static func live(_ board: NSPasteboard = .general) -> URLCleanerSystem {
        let title = NSPasteboard.PasteboardType("public.url-name")
        return URLCleanerSystem(
            observe: { ClipboardManager.willCapture = $0 },
            itemTypes: { board.pasteboardItems?.map { $0.types.map(\.rawValue) } ?? [] },
            isDeclared: { UTType($0)?.isDeclared == true },
            // Some "copy link" commands put the link on the pasteboard only as a URL.
            text: { board.string(forType: .string) ?? board.string(forType: .URL) },
            replace: { link in
                let hadURL = board.types?.contains(.URL) == true
                let name = board.string(forType: title)
                board.clearContents()
                board.setString(link, forType: .string)
                if hadURL { board.setString(link, forType: .URL) }
                if let name { board.setString(name, forType: title) }
                board.setData(Data(), forType: ClipboardManager.internalType)
            }
        )
    }
}
