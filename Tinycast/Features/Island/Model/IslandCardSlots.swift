import CoreGraphics

/// Where a page's cards sit: `columns` in fixed slots, a `cards` row four across (#1128).
enum IslandCardSlots {
    /// Never fewer columns than this, so one machine's cards keep the width they have beside two more.
    static let minimumColumns = 3
    static let rowColumns = 4

    struct Card: Equatable, Sendable {
        var column: Int
        var hollow: Bool
        /// The card's own height at the column's width.
        var natural: CGFloat
    }

    static func columnWidth(width: CGFloat, columns: Int, gap: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max((width - gap * (count - 1)) / count, 0)
    }

    /// A full card is as tall as the tallest full card; a hollow one is half a slot less half the gap.
    static func slot(_ cards: [Card], gap: CGFloat) -> CGFloat {
        let full = cards.filter { !$0.hollow }.map(\.natural).max() ?? 0
        let hollow = cards.filter(\.hollow).map(\.natural).max().map { 2 * $0 + gap } ?? 0
        return max(full, hollow)
    }

    static func count(groups: Int) -> Int { max(groups, minimumColumns) }

    /// Each card's frame, column by column, in the order given; `columns` comes from `count(groups:)`.
    static func columns(_ cards: [Card], width: CGFloat, columns count: Int, gap: CGFloat) -> [CGRect] {
        let columnWidth = columnWidth(width: width, columns: count, gap: gap)
        let slot = slot(cards, gap: gap)
        var tops = Array(repeating: CGFloat(0), count: count)
        return cards.map { card in
            guard tops.indices.contains(card.column) else { return .zero }
            let height = card.hollow ? (slot - gap) / 2 : slot
            let frame = CGRect(x: CGFloat(card.column) * (columnWidth + gap), y: tops[card.column],
                               width: columnWidth, height: height)
            tops[card.column] += height + gap
            return frame
        }
    }

    /// Four across and wrapping, every card as tall as the tallest.
    static func row(_ naturals: [CGFloat], width: CGFloat, gap: CGFloat) -> [CGRect] {
        let columnWidth = columnWidth(width: width, columns: rowColumns, gap: gap)
        let height = naturals.max() ?? 0
        return naturals.indices.map { index in
            CGRect(x: CGFloat(index % rowColumns) * (columnWidth + gap),
                   y: CGFloat(index / rowColumns) * (height + gap), width: columnWidth, height: height)
        }
    }
}
