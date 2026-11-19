import Foundation

/// The board as the island's Agents page: a column per machine, the shared accounts as the Other row.
enum AgentPage {
    static let id = "agents"
    static let symbol = "gauge.with.needle"
    /// Agents lead the tabs (island-shell "Pages").
    static let order = 0
    static let gridColumns = 3

    static func page(_ board: AgentBoard) -> IslandPage {
        let none = String(localized: "No plans found", table: "NotchcastAgents")
        var blocks: [IslandPageBlock] = []
        if board.isEmpty {
            blocks.append(.row(IslandPageRow(
                symbol: "magnifyingglass", title: none,
                detail: String(localized: "Add a Claude account in Settings › Notchcast › Agents.", table: "NotchcastAgents"))))
        }
        let columns = board.columns.count == 1 ? flow(board.columns[0])
            : board.columns.map { IslandCardGroup(title: $0.title, cards: $0.cards.map(card)) }
        if !columns.isEmpty { blocks.append(.columns(columns)) }
        if !board.other.isEmpty {
            blocks.append(.cards(IslandCardGroup(title: String(localized: "Other", table: "NotchcastAgents"),
                                                 cards: board.other.map(card))))
        }
        if let footnote = board.footnote { blocks.append(.row(IslandPageRow(symbol: "info.circle", title: footnote))) }
        let reading = String(localized: "Reading…", table: "NotchcastAgents")
        return IslandPage(
            id: id, title: String(localized: "Agents", table: "NotchcastAgents"), symbol: symbol, order: order,
            line: IslandPageLine(symbol: symbol, text: board.homeLine ?? (board.isEmpty ? none : reading)),
            blocks: blocks)
    }

    /// One Mac's cards dealt round the grid in Settings order, so a spent or added card moves no other.
    static func flow(_ column: AgentColumn) -> [IslandCardGroup] {
        let count = min(gridColumns, column.cards.count)
        return (0..<count).map { index in
            IslandCardGroup(title: index == 0 ? column.title : "",
                            cards: stride(from: index, to: column.cards.count, by: gridColumns).map { card(column.cards[$0]) })
        }
    }

    static func card(_ agent: AgentCard) -> IslandCard {
        let body: IslandCard.Body =
            switch agent.body {
            case .meters(let meters):
                .meters(meters.map {
                    IslandCardMeter(label: $0.label, value: $0.value, trailing: $0.trailing, fraction: $0.fraction,
                                    tick: $0.tick, thick: $0.thick, warning: $0.warning, note: $0.note)
                })
            case .notice(let glyph, let headline): .notice(symbol: glyph, headline: headline, detail: agent.detail)
            }
        return IslandCard(
            title: agent.title, tag: agent.credit.map { IslandCardTag(symbol: "arrow.counterclockwise", text: $0) },
            hollow: agent.hollow, body: body, dimmed: agent.dimmed, caption: agent.caption, spoken: agent.spoken)
    }
}
