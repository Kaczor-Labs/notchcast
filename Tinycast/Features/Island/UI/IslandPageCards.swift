import SwiftUI

/// The `columns` block: a title over each column, its cards in fixed slots (design §17, #1128).
struct IslandCardColumnsView: View {
    let groups: [IslandCardGroup]
    @Environment(\.metrics) private var metrics

    var body: some View {
        let gap = metrics.spacing.md
        let count = IslandCardSlots.count(groups: groups.count)
        let width = IslandCardWidth.content(metrics)
        let columnWidth = IslandCardSlots.columnWidth(width: width, columns: count, gap: gap)
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            HStack(spacing: gap) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    IslandCardHeader(title: group.title).frame(width: columnWidth, alignment: .leading)
                }
            }
            IslandCardLayout(mode: .columns(count), gap: gap) {
                ForEach(Array(groups.enumerated()), id: \.offset) { column, group in
                    ForEach(Array(group.cards.enumerated()), id: \.offset) { _, card in
                        IslandCardView(card: card, narrow: count >= IslandCardSlots.rowColumns)
                            .layoutValue(key: IslandCardColumn.self, value: column)
                            .layoutValue(key: IslandCardHollow.self, value: card.hollow)
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The `cards` block: a titled row, four across, every card as tall as the tallest.
struct IslandCardRowView: View {
    let group: IslandCardGroup
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            IslandCardHeader(title: group.title)
            IslandCardLayout(mode: .row, gap: metrics.spacing.md) {
                ForEach(Array(group.cards.enumerated()), id: \.offset) { _, card in IslandCardView(card: card, narrow: true) }
            }
        }
        .frame(width: IslandCardWidth.content(metrics), alignment: .leading)
    }
}

/// The card blocks keep the launcher panel's width whatever they hold, so slots never reflow.
enum IslandCardWidth {
    static func content(_ metrics: InterfaceMetrics) -> CGFloat { metrics.size.panelWidth - 2 * metrics.spacing.md }
}

private struct IslandCardColumn: LayoutValueKey { static let defaultValue = 0 }
private struct IslandCardHollow: LayoutValueKey { static let defaultValue = false }

/// Places the cards where `IslandCardSlots` says, each proposed its slot's size.
private struct IslandCardLayout: Layout {
    enum Mode { case columns(Int), row }

    let mode: Mode
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        switch mode {
        case .columns(let count):
            let columnWidth = IslandCardSlots.columnWidth(width: width, columns: count, gap: gap)
            let cards = subviews.map { subview in
                IslandCardSlots.Card(column: subview[IslandCardColumn.self], hollow: subview[IslandCardHollow.self],
                                     natural: subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height)
            }
            return IslandCardSlots.columns(cards, width: width, columns: count, gap: gap)
        case .row:
            let columnWidth = IslandCardSlots.columnWidth(width: width, columns: IslandCardSlots.rowColumns, gap: gap)
            let naturals = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
            return IslandCardSlots.row(naturals, width: width, gap: gap)
        }
    }
}

struct IslandCardHeader: View {
    let title: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.xl)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One card: full on the key-cap fill, hollow as an outline; dimmed while its numbers are old.
struct IslandCardView: View {
    let card: IslandCard
    var narrow = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.md) {
                Text(card.title).font(metrics.typography.panelTitle)
                    .foregroundStyle(card.hollow ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                if let tag = card.tag { IslandCardTagView(tag: tag) }
            }
            .lineLimit(1)
            switch card.body {
            case .meters(let meters):
                ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                    IslandCardMeterView(meter: meter, narrow: narrow)
                }
            case .notice(let symbol, let headline, let detail):
                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    HStack(spacing: metrics.spacing.xs) {
                        if let symbol {
                            SymbolImage(name: symbol, size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                        monochrome: true)
                        }
                        Text(headline).font(metrics.typography.panelTitle)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    if let detail {
                        Text(detail).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .lineLimit(1)
            }
            if let caption = card.caption {
                Text(caption).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(metrics.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if card.hollow {
                shape.strokeBorder(Theme.Colors.separator, lineWidth: 1)
            } else {
                shape.fill(NotchTheme.Colors.keyCapFill)
            }
        }
        .opacity(card.dimmed ? NotchTheme.Opacity.disabled : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spoken ?? Self.spoken(card))
    }

    static func spoken(_ card: IslandCard) -> String {
        var parts = [card.title] + [card.tag?.text].compactMap(\.self)
        switch card.body {
        case .meters(let meters):
            parts += meters.map { [$0.label, $0.value, $0.trailing, $0.note].compactMap(\.self).joined(separator: ", ") }
        case .notice(_, let headline, let detail): parts += [headline, detail].compactMap(\.self)
        }
        return (parts + [card.caption].compactMap(\.self)).joined(separator: ". ")
    }
}

/// A chip beside the card's title, such as a credit the account holds.
private struct IslandCardTagView: View {
    let tag: IslandCardTag
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            if let symbol = tag.symbol {
                SymbolImage(name: symbol, size: metrics.scaled(Theme.Typography.menuSymbolSize), monochrome: true)
            }
            Text(tag.text).font(metrics.typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.xxs)
        .background(Capsule().strokeBorder(NotchTheme.Colors.cardRule, lineWidth: 1))
    }
}

/// Label, value and trailing text over the bar; the even-pace tick on it; the note under it.
struct IslandCardMeterView: View {
    let meter: IslandCardMeter
    /// Four across, "55% left in 2 d 15 h" outgrows one line, so the trailing text drops under the value.
    var narrow = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let ink = meter.warning ? NotchTheme.Colors.islandWarning : Theme.Colors.textPrimary
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            HStack(spacing: metrics.spacing.sm) {
                Text(meter.label).foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: metrics.spacing.md)
                Text(meter.value).foregroundStyle(ink)
                if !narrow, let trailing = meter.trailing { Text(trailing).foregroundStyle(Theme.Colors.textPrimary) }
            }
            .font(metrics.typography.rowTrailing.monospacedDigit())
            .lineLimit(1)
            if narrow, let trailing = meter.trailing {
                Text(trailing).font(metrics.typography.rowTrailing.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            IslandCardBar(fraction: meter.fraction, tick: meter.tick, thick: meter.thick, ink: ink)
            if let note = meter.note {
                Text(note).font(metrics.typography.rowTrailing.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
            }
        }
    }
}

/// A track with its fill from the leading edge and a tick standing past both of its edges.
private struct IslandCardBar: View {
    let fraction: Double
    let tick: Double?
    let thick: Bool
    let ink: Color
    @Environment(\.metrics) private var metrics

    var body: some View {
        let height = metrics.scaled(thick ? NotchTheme.Size.islandMeterThick : NotchTheme.Size.islandMeterThin)
        let tickHeight = height + 2 * metrics.spacing.xxs
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                let filled = fraction.isFinite ? min(max(fraction, 0), 1) : 0
                Capsule().fill(Theme.Colors.border).frame(height: height)
                Capsule().fill(ink).frame(width: max(filled > 0 ? height : 0, width * filled), height: height)
                // A tick at either end only repeats the bar's own edge, so it shows inside 2–98 %.
                if let tick, tick.isFinite, tick > 0.02, tick < 0.98 {
                    Rectangle().fill(Theme.Colors.textPrimary)
                        .frame(width: metrics.spacing.xxs, height: tickHeight)
                        .offset(x: width * tick - metrics.spacing.xxs / 2)
                }
            }
            .frame(height: tickHeight)
        }
        .frame(height: tickHeight)
        .accessibilityHidden(true)
    }
}
