import AppKit

extension Task: PlainPasteTimer where Success == Void, Failure == Never {}

extension PastePlainTextSystem {
    static let live = PastePlainTextSystem(
        makeBoard: { GeneralPlainPasteBoard() },
        postCommandV: { Paster.postCommandV() },
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
    var hasFileURLs: Bool { board.types?.contains(.fileURL) == true }
    var string: String? { board.string(forType: .string) }
    var ownMarker: String { ClipboardManager.internalType.rawValue }

    func rtfText() -> String? {
        board.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string }
    }

    func rtfdText() -> String? {
        board.data(forType: .rtfd).flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil)?.string }
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
                    return .failed(changeCount: board.changeCount)
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
