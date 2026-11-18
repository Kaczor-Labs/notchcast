import AppKit

extension PastePlainTextSystem {
    /// Covers the palette handing focus back when the command runs from the launcher.
    private static let focusDelay: Duration = .milliseconds(80)

    static let live = PastePlainTextSystem(
        makeBoard: { GeneralPlainPasteBoard() },
        sendPaste: {
            Task { @MainActor in
                try? await Task.sleep(for: focusDelay)
                Paster.postCommandV()
            }
        },
        after: { delay, work in
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                work()
            }
        }
    )
}

@MainActor
private final class GeneralPlainPasteBoard: PlainPasteBoard {
    private let board = NSPasteboard.general

    var changeCount: Int { board.changeCount }
    var hasFileURLs: Bool { board.types?.contains(.fileURL) == true }
    var string: String? { board.string(forType: .string) }

    func rtfText() -> String? {
        board.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string }
    }

    func rtfdText() -> String? {
        board.data(forType: .rtfd).flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil)?.string }
    }

    func snapshot() -> [[PlainPasteEntry]] {
        (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { PlainPasteEntry(type: type.rawValue, data: $0) } }
        }
    }

    func writeOwn(_ text: String) -> Int {
        Paster.copyString(text)
        return board.changeCount
    }

    func restoreOwn(_ items: [[PlainPasteEntry]]) -> Int {
        let copies = items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: .init(entry.type)) }
            return item
        }
        copies.first?.setData(Data(), forType: ClipboardManager.internalType)
        board.clearContents()
        board.writeObjects(copies)
        return board.changeCount
    }
}
