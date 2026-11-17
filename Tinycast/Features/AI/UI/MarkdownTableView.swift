import SwiftUI

struct MarkdownTableView: View {

    @Environment(\.metrics) private var metrics
    @Environment(\.paletteOnIsland) private var onIsland
    let table: MarkdownBlock.Table

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline, horizontalSpacing: metrics.spacing.xl,
            verticalSpacing: metrics.spacing.sm
        ) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    Text(MarkdownInline.attributed(cell, metrics))
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .gridColumnAlignment(alignment(at: column))
                }
            }
            GridRow {
                Rectangle()
                    .fill(.islandSeparator)
                    .frame(height: Theme.Size.hairline)
                    .gridCellUnsizedAxes(.horizontal)
                    .gridCellColumns(table.header.count)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(MarkdownInline.attributed(cell, metrics))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // Given only a width, Grid measures a wrapping row a line short of what it draws.
        .fixedSize(horizontal: false, vertical: true)
        .padding(metrics.spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.islandCard(onIsland: onIsland), style: .continuous)
                .fill(.islandCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.islandCard(onIsland: onIsland), style: .continuous)
                .stroke(.islandEdge()))
    }

    private func alignment(at column: Int) -> HorizontalAlignment {
        switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
