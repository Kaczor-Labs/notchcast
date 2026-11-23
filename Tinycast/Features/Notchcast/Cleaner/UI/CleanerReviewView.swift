import SwiftUI

struct CleanerReviewView: View {
    @Environment(\.metrics) private var metrics

    let rows: [CleanerItem]
    let selected: CleanerItem?
    let checked: Set<CleanerItem.ID>
    let scroll: ScrollIntent
    let onCheck: (CleanerItem.ID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            results
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline)
                .accessibilityHidden(true)
            ScrollView {
                if let selected {
                    CleanerItemDetail(item: selected)
                }
            }
            .hideNativeScrollers()
            .thinScrollbar()
            .frame(width: metrics.size.clipboardListWidth)
            .id(selected?.id)
        }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || rows[index - 1].area.kind != item.area.kind {
                            SectionHeader(title: item.area.kind.cleanerTitle, isFirst: index == 0)
                        }
                        CleanerReviewRow(
                            item: item, selected: item.id == selected?.id, checked: checked.contains(item.id),
                            toggle: { onCheck(item.id) })
                            .id(item.id.path)
                            .selectionFrame(item.id == selected?.id)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .scrollOriginAnchor()
            }
            .hideNativeScrollers()
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selected?.id.path, atOrigin: selected?.id == rows.first?.id, proxy: proxy)
        }
    }
}

private struct CleanerReviewRow: View {
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    let item: CleanerItem
    let selected: Bool
    let checked: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            if item.standing.isSelectable {
                Toggle(isOn: Binding(get: { checked }, set: { _ in toggle() })) {
                    Text(verbatim: item.id.lastPathComponent)
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            } else {
                SymbolImage(name: "lock.fill", size: metrics.size.checkbox)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                    .accessibilityHidden(true)
            }

            Button(action: toggle) {
                HStack(spacing: metrics.spacing.md) {
                    VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                        Text(verbatim: item.id.lastPathComponent)
                            .font(metrics.typography.rowTitle)
                        Text(item.standing.cleanerLabel)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer(minLength: metrics.spacing.md)
                    if let size = item.size {
                        Text(verbatim: size.formatted)
                            .font(metrics.typography.rowTrailing)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : Color.clear,
            in: RoundedRectangle(cornerRadius: metrics.radius.row))
        .armedHover($hovered)
    }
}

private struct CleanerItemDetail: View {
    @Environment(\.metrics) private var metrics
    let item: CleanerItem

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            Text(verbatim: item.id.lastPathComponent)
                .font(metrics.typography.panelTitle)
                .accessibilityAddTraits(.isHeader)
                .textSelection(.enabled)
            Text(verbatim: (item.id.path as NSString).abbreviatingWithTildeInPath)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textSelection(.enabled)
            Text(item.standing.cleanerDetail)
                .font(metrics.typography.rowTitle)
            if let size = item.size {
                Text(verbatim: size.formatted)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            } else {
                Text("Size unknown", tableName: "NotchcastCleaner")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.spacing.xl)
    }
}
