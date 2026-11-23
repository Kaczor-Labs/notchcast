import Foundation

/// The board as the island draws it: the Threads page, the resting count and the notices (sheet r1).
enum ThreadsPage {
    static let id = "threads"
    static let symbol = "bubble.left.and.exclamationmark.bubble.right"
    /// After Agents, before the system pages.
    static let order = 5
    static let batchNotice = "threads.batch"
    static let rowPrefix = "open."

    /// Nil while no file is set, or once nothing waits, nothing is put off and every machine reports.
    static func page(_ board: ThreadsBoard) -> IslandPage? {
        guard board.configured else { return nil }
        let waiting = board.waiting
        let later = board.later
        var blocks: [IslandPageBlock] = []
        if board.notReporting {
            let detail = board.documentAge.map {
                String(localized: "Last update \(ThreadsBoard.duration($0)) ago. This list may be out of date.",
                       table: "NotchcastThreads")
            } ?? String(localized: "No readable waits file at the path in Settings.", table: "NotchcastThreads")
            blocks.append(.row(IslandPageRow(symbol: "antenna.radiowaves.left.and.right.slash",
                                             title: notReporting, detail: detail)))
        }
        for (machine, age) in board.silentMachines {
            let name = machine.uppercased()
            let title = age.map {
                String(localized: "\(name) last heard \(ThreadsBoard.duration($0)) ago", table: "NotchcastThreads")
            } ?? String(localized: "\(name) has not reported", table: "NotchcastThreads")
            blocks.append(.row(IslandPageRow(symbol: "clock.badge.exclamationmark", title: title, detail: String(
                localized: "Its threads may be out of date", table: "NotchcastThreads"))))
        }
        if waiting.isEmpty, !board.notReporting {
            if later.isEmpty, blocks.isEmpty { return nil }
            blocks.append(.row(IslandPageRow(symbol: "checkmark.circle", title: nothingWaits)))
        }
        blocks += waiting.enumerated().map { .row(row($1, index: $0, board: board)) }
        if !later.isEmpty {
            blocks.append(.row(IslandPageRow(title: String(localized: "Not waiting on you", table: "NotchcastThreads"))))
            blocks += later.enumerated().map { .row(row($1, index: waiting.count + $0, board: board)) }
        }
        return IslandPage(
            id: id, title: String(localized: "Threads", table: "NotchcastThreads"), symbol: symbol, order: order,
            badge: waiting.count, line: IslandPageLine(symbol: symbol, text: line(board, waiting: waiting)),
            blocks: blocks)
    }

    /// The rows in page order, so a row's action id indexes this list.
    static func rows(_ board: ThreadsBoard) -> [ThreadsDocument.Wait] { board.waiting + board.later }

    static func row(_ wait: ThreadsDocument.Wait, index: Int, board: ThreadsBoard) -> IslandPageRow {
        let trailing = "\(wait.machine.uppercased()) · \(ThreadsBoard.duration(board.age(of: wait)))"
        return IslandPageRow(
            id: ThreadsLink.url(wait) == nil ? nil : rowPrefix + String(index), symbol: symbol(wait),
            title: ThreadsBoard.title(wait), detail: detail(wait), trailing: trailing)
    }

    /// The count beside the notch or in the pill, red while a run among them failed (sheet r1, Q4 and Q5).
    static func status(_ board: ThreadsBoard) -> IslandStatus? {
        let count = board.waiting.count
        guard board.configured, count > 0 else { return nil }
        let failed = board.failedCount
        let label = failed == 0 ? waitCount(count)
            : String(localized: "\(waitCount(count)), \(failed) failed", table: "NotchcastThreads")
        return IslandStatus(id: id, symbol: symbol, text: String(count), label: label,
                            tone: failed > 0 ? .critical : nil)
    }

    /// A failed run alone, everything else in one notice (sheet r1, Q3); each pairs with the wait it opens.
    static func notices(_ fresh: [ThreadsDocument.Wait]) -> [(notice: IslandNotice, wait: ThreadsDocument.Wait?)] {
        let failed = fresh.filter { $0.kind == .failedRun }
        let asks = fresh.filter { $0.kind != .failedRun }
        var notices = failed.map { (notice($0), Optional($0)) }
        if asks.count == 1 {
            notices.insert((notice(asks[0]), asks[0]), at: 0)
        } else if asks.count > 1 {
            let names = asks.map(ThreadsBoard.title).joined(separator: ", ")
            let text = String(localized: "\(asks.count) threads wait on you: \(names)", table: "NotchcastThreads")
            notices.insert((IslandNotice(id: batchNotice, symbol: symbol, text: text), nil), at: 0)
        }
        return notices
    }

    static func notice(_ wait: ThreadsDocument.Wait) -> IslandNotice {
        let title = ThreadsBoard.title(wait)
        let text: String =
            switch wait.kind {
            case .failedRun: String(localized: "\(title) failed", table: "NotchcastThreads")
            case .approval: String(localized: "\(title) wants your approval", table: "NotchcastThreads")
            case .secret: String(localized: "\(title) needs a secret from you", table: "NotchcastThreads")
            case .link: String(localized: "\(title) needs you to open a link", table: "NotchcastThreads")
            case .question, .guestMessage, .doorAsk, .other:
                wait.question.map { String(localized: "\(title) asks: \($0)", table: "NotchcastThreads") }
                    ?? String(localized: "\(title) asks you", table: "NotchcastThreads")
            }
        return IslandNotice(id: "threads." + (wait.id ?? title), symbol: symbol(wait), text: text,
                            isFailure: wait.kind == .failedRun)
    }

    static func symbol(_ wait: ThreadsDocument.Wait) -> String {
        if wait.later { return "clock" }
        return switch wait.kind {
        case .question, .other: "questionmark.bubble"
        case .doorAsk: "person.bubble"
        case .guestMessage: "bubble.left"
        case .failedRun: "exclamationmark.triangle"
        case .approval: "checkmark.shield"
        case .secret: "key"
        case .link: "link"
        }
    }

    static func detail(_ wait: ThreadsDocument.Wait) -> String? {
        if wait.later {
            return wait.question.map { String(localized: "Later: \($0)", table: "NotchcastThreads") }
        }
        return switch wait.kind {
        case .failedRun: String(localized: "Failed", table: "NotchcastThreads")
        case .approval: String(localized: "Wants your approval", table: "NotchcastThreads")
        case .secret: String(localized: "Needs a secret", table: "NotchcastThreads")
        case .link: String(localized: "Needs you to open a link", table: "NotchcastThreads")
        case .question, .guestMessage, .doorAsk, .other: wait.question
        }
    }

    private static var notReporting: String { String(localized: "t3chad is not reporting", table: "NotchcastThreads") }
    private static var nothingWaits: String { String(localized: "Nothing waits on you", table: "NotchcastThreads") }

    private static func waitCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 thread waits on you", table: "NotchcastThreads")
            : String(localized: "\(count) threads wait on you", table: "NotchcastThreads")
    }

    private static func line(_ board: ThreadsBoard, waiting: [ThreadsDocument.Wait]) -> String {
        if board.notReporting { return notReporting }
        guard waiting.count == 1 else { return waiting.isEmpty ? nothingWaits : waitCount(waiting.count) }
        let title = ThreadsBoard.title(waiting[0])
        return waiting[0].kind == .failedRun ? String(localized: "\(title) failed", table: "NotchcastThreads")
            : String(localized: "\(title) asks you", table: "NotchcastThreads")
    }
}
