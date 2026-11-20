import Foundation

/// One pasteboard type and its bytes, copied out so the original survives a temporary write.
struct PlainPasteEntry: Equatable, Sendable {
    let type: String
    let data: Data
}

/// Every item and type on the board, with the change count from before the read.
struct PlainPasteSnapshot: Equatable, Sendable {
    let items: [[PlainPasteEntry]]
    let changeCount: Int
}

enum PlainPasteWrite: Equatable, Sendable {
    case written(changeCount: Int)
    /// Someone wrote the board since the expected count; nothing was touched.
    case superseded
    /// The board now reads `changeCount`, cleared when the failure came after the clear.
    case failed(changeCount: Int)
}

/// The clipboard as the engine sees it; the shipped one is `NSPasteboard.general`.
@MainActor
protocol PlainPasteBoard: AnyObject {
    var changeCount: Int { get }
    /// Every type on the board, named without reading any data.
    var types: [String] { get }
    var string: String? { get }
    /// The type clipboard history skips; it marks the temporary write and nothing else.
    var ownMarker: String { get }
    func rtfText() -> String?
    func rtfdText() -> String?
    func htmlText() -> String?
    /// Each item's types, in order.
    var itemTypes: [[String]] { get }
    func data(item: Int, type: String) -> Data?
    /// Builds every item first, then clears and writes only if the board still reads `changeCount`.
    func write(_ items: [[PlainPasteEntry]], ifChangeCount changeCount: Int) -> PlainPasteWrite
}

/// Lends the clipboard's text unformatted, then puts the original back unless something replaced it.
@MainActor
final class PlainPasteEngine {
    enum Outcome: Equatable {
        /// The plain text is on the board at `changeCount`; ⌘V goes out only while it still is.
        case plain(changeCount: Int)
        /// The board could not be read or written whole, so nothing is pasted.
        case refused
    }

    static let restoreDelay: Duration = .milliseconds(500)

    private let board: any PlainPasteBoard
    private let prepareWrite: @MainActor () -> Void
    private let didWrite: @MainActor (_ changeCount: Int) -> Void
    private var pending: (items: [[PlainPasteEntry]], changeCount: Int, retries: Int)?

    init(
        board: any PlainPasteBoard, prepareWrite: @escaping @MainActor () -> Void,
        didWrite: @escaping @MainActor (_ changeCount: Int) -> Void
    ) {
        self.board = board
        self.prepareWrite = prepareWrite
        self.didWrite = didWrite
    }

    var isRestorePending: Bool { pending != nil }
    var changeCount: Int { board.changeCount }

    /// Nil leaves the paste to the app: files, a lone picture, or no text.
    func text() -> String? {
        PlainPastePolicy.text(
            types: board.types, string: { board.string }, rtf: board.rtfText, rtfd: board.rtfdText,
            html: board.htmlText)
    }

    /// Lends text read at count `readAt`, refused if the board moved; restore earlier pastes first.
    func lend(_ text: String, readAt changeCount: Int) -> Outcome {
        prepareWrite()
        guard let snapshot = snapshot(), snapshot.changeCount == changeCount else { return .refused }
        let temporary = [[
            PlainPasteEntry(type: "public.utf8-plain-text", data: Data(text.utf8)),
            PlainPasteEntry(type: board.ownMarker, data: Data()),
        ]]
        switch board.write(temporary, ifChangeCount: snapshot.changeCount) {
        case .written(let changeCount):
            didWrite(changeCount)
            pending = (snapshot.items, changeCount, 1)
            return .plain(changeCount: changeCount)
        case .superseded:
            return .refused
        case .failed(let changeCount):
            guard changeCount != snapshot.changeCount else { return .refused }
            pending = (snapshot.items, changeCount, 1)
            restorePending()
            return .refused
        }
    }

    /// Nil when a type has no data; a copy made mid-read fails the write's pre-read count instead.
    private func snapshot() -> PlainPasteSnapshot? {
        let changeCount = board.changeCount
        var items: [[PlainPasteEntry]] = []
        for (index, types) in board.itemTypes.enumerated() {
            var entries: [PlainPasteEntry] = []
            for type in types {
                guard let data = board.data(item: index, type: type) else { return nil }
                entries.append(PlainPasteEntry(type: type, data: data))
            }
            items.append(entries)
        }
        return PlainPasteSnapshot(items: items, changeCount: changeCount)
    }

    /// Puts the original back while the board holds our write; a failed write keeps one retry.
    func restorePending() {
        guard let pending else { return }
        switch board.write(pending.items, ifChangeCount: pending.changeCount) {
        case .written(let changeCount):
            self.pending = nil
            didWrite(changeCount)
        case .superseded:
            self.pending = nil
        case .failed(let changeCount):
            self.pending = pending.retries > 0 ? (pending.items, changeCount, pending.retries - 1) : nil
        }
    }
}
