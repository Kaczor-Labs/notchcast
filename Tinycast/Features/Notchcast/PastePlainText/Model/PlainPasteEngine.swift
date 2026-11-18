import Foundation

/// One pasteboard type and its bytes, copied out so the original survives a temporary write.
struct PlainPasteEntry: Equatable, Sendable {
    let type: String
    let data: Data
}

/// The clipboard as the engine sees it; the shipped one is `NSPasteboard.general`.
@MainActor
protocol PlainPasteBoard: AnyObject {
    var changeCount: Int { get }
    var hasFileURLs: Bool { get }
    var string: String? { get }
    func rtfText() -> String?
    func rtfdText() -> String?
    func snapshot() -> [[PlainPasteEntry]]
    /// Both writes carry clipboard history's own-change marker; each returns the new change count.
    func writeOwn(_ text: String) -> Int
    func restoreOwn(_ items: [[PlainPasteEntry]]) -> Int
}

/// Pastes the clipboard's text unformatted, then puts the original back unless something replaced it.
@MainActor
final class PlainPasteEngine {
    enum Outcome: Equatable {
        /// The plain text went out; `restore` with this token puts the original back.
        case plain(token: Int)
        case passThrough
    }

    static let restoreDelay: Duration = .milliseconds(500)

    private let board: any PlainPasteBoard
    private let sendPaste: @MainActor () -> Void
    private var pending: (token: Int, items: [[PlainPasteEntry]], changeCount: Int)?
    private var lastToken = 0

    init(board: any PlainPasteBoard, sendPaste: @escaping @MainActor () -> Void) {
        self.board = board
        self.sendPaste = sendPaste
    }

    var isRestorePending: Bool { pending != nil }

    /// Plain string first, then RTF, then RTFD; file URLs or no text leave the paste to the app.
    static func text(
        hasFileURLs: Bool, string: String?, rtf: () -> String?, rtfd: () -> String?
    ) -> String? {
        guard !hasFileURLs else { return nil }
        if let string, !string.isEmpty { return string }
        if let rtf = rtf(), !rtf.isEmpty { return rtf }
        return rtfd().flatMap { $0.isEmpty ? nil : $0 }
    }

    func paste() -> Outcome {
        restorePending()
        guard let text = Self.text(
            hasFileURLs: board.hasFileURLs, string: board.string, rtf: board.rtfText, rtfd: board.rtfdText)
        else {
            sendPaste()
            return .passThrough
        }
        let items = board.snapshot()
        lastToken += 1
        pending = (lastToken, items, board.writeOwn(text))
        sendPaste()
        return .plain(token: lastToken)
    }

    /// A stale token is a timer that a newer paste already overtook.
    func restore(token: Int) {
        guard pending?.token == token else { return }
        restorePending()
    }

    func restorePending() {
        guard let pending else { return }
        self.pending = nil
        guard board.changeCount == pending.changeCount else { return }
        _ = board.restoreOwn(pending.items)
    }
}
