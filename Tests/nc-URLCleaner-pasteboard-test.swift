// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/URLCleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/URLCleaner/Service/*.swift

import AppKit

/// Stands in for the clipboard poll's owner: the same marker, and the hook nobody calls here.
@MainActor
enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    static var willCapture: (@MainActor () -> Void)?
}

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

@MainActor
func rewrite() {
    let title = NSPasteboard.PasteboardType("public.url-name")
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let system = URLCleanerSystem.live(board)
    let isPlain = { URLCleanerPolicy.isPlainLink(itemTypes: system.itemTypes(), isDeclared: system.isDeclared) }

    board.clearContents()
    board.setString("https://x.com/a?utm_source=y", forType: .string)
    board.setString("https://x.com/a?utm_source=y", forType: .URL)
    board.setString("A page", forType: title)
    expect(isPlain(), "a link with its URL and title is a plain link")
    system.replace("https://x.com/a")
    expect(board.string(forType: .string) == "https://x.com/a", "the rewrite holds the cleaned string")
    expect(board.string(forType: .URL) == "https://x.com/a", "and the URL the copy had")
    expect(board.string(forType: title) == "A page", "and the link's title")
    expect(board.types?.contains(ClipboardManager.internalType) == true, "and Notchcast's marker")
    expect(!isPlain(), "so the cleaner never takes its own write for a new link")

    board.clearContents()
    board.setString("https://x.com/a?utm_source=y", forType: .string)
    system.replace("https://x.com/a")
    expect(board.string(forType: .string) == "https://x.com/a", "a bare string is rewritten")
    expect(board.types?.contains(.URL) == false && board.types?.contains(title) == false, "with no URL or title added")
    expect(!isPlain(), "and is marked too")
}

@main
@MainActor
enum URLCleanerPasteboardTests {
    static func main() {
        rewrite()
        guard failures == 0 else {
            print("\(failures) of \(checks) checks failed")
            exit(1)
        }
        print("PASS: \(checks) URL Cleaner pasteboard checks")
    }
}
