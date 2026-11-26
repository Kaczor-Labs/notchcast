import SwiftUI

struct CleanerScreen: PaletteScreen {
    let module: CleanerModule
    let reviewID: UUID
    let query: String
    let selectRow: (Int) -> Void

    private var session: CleanerSession { module.session }

    var rows: [CleanerItem] {
        guard session.phase == .review || session.phase == .confirming else { return [] }
        let groups = Dictionary(grouping: session.items(matching: query), by: \.area.kind)
        return CleanerArea.Kind.allCases.flatMap { groups[$0] ?? [] }
    }

    var hidesSearchField: Bool { session.phase != .review && session.phase != .confirming }
    var actsWithoutRows: Bool { true }

    var primaryActionTitle: String {
        switch session.phase {
        case .needsAccess: String(localized: "Open System Settings…", table: "NotchcastCleaner")
        case .scanFailed, .done: String(localized: "Scan Again", table: "NotchcastCleaner")
        case .review where session.hiddenSelectionCount(among: rows) > 0:
            String(localized: "Show Selected Items", table: "NotchcastCleaner")
        default: String(localized: "Move to Trash", table: "NotchcastCleaner")
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        switch session.phase {
        case .review, .needsAccess, .done, .scanFailed: true
        default: false
        }
    }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        session.phase != .review || session.selection?.checked.isEmpty == false
    }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        switch session.phase {
        case .needsAccess: Permissions.openFullDiskAccessSettings()
        case .scanFailed, .done: module.scan(for: reviewID)
        case .review: module.activateReview(visibleItems: rows) { module.openScreen(rescan: false) }
        default: break
        }
    }

    func secondary(at selection: Int) -> Bool {
        let rows = rows
        guard rows.indices.contains(selection), rows[selection].standing.isSelectable else { return false }
        toggle(rows[selection].id)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .restart else { return false }
        module.scan(for: reviewID)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        switch session.phase {
        case .idle:
            Color.clear
        case .needsAccess:
            EmptyResults(
                text: String(localized: "Full Disk Access required", table: "NotchcastCleaner"),
                detail: String(localized: "Grant access in System Settings, then scan again.",
                               table: "NotchcastCleaner"), systemImage: "lock.fill")
        case .scanning:
            CleanerActivityView(
                text: String(localized: "Scanning for files…", table: "NotchcastCleaner"),
                count: session.items.count)
        case .review, .confirming:
            review(selection: selection, scroll: scroll)
        case .cleaning:
            CleanerActivityView(
                text: String(localized: "Moving items to the Trash…", table: "NotchcastCleaner"), count: nil)
        case .done:
            EmptyResults(text: module.result?.text ?? "", systemImage: module.result?.symbol ?? "trash")
        case .scanFailed:
            EmptyResults(
                text: String(localized: "Couldn’t scan for files. Try again.", table: "NotchcastCleaner"),
                systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private func review(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        CleanerReviewLayout(
            rows: rows, selected: rows.indices.contains(selection) ? rows[selection] : nil,
            checked: session.selection?.checked ?? [], hiddenCount: session.hiddenSelectionCount(among: rows),
            bytes: session.selectedBytes, hasItems: !session.items.isEmpty, scroll: scroll,
            onCheck: toggle, onSelect: selectRow)
    }

    private func toggle(_ id: CleanerItem.ID) {
        session.setChecked(id, checked: session.selection?.checked.contains(id) != true)
    }
}

private struct CleanerReviewLayout: View {
    @Environment(\.metrics) private var metrics

    let rows: [CleanerItem]
    let selected: CleanerItem?
    let checked: Set<CleanerItem.ID>
    let hiddenCount: Int
    let bytes: Int64
    let hasItems: Bool
    let scroll: ScrollIntent
    let onCheck: (CleanerItem.ID) -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                EmptyResults(text: hasItems
                    ? String(localized: "No matching items", table: "NotchcastCleaner")
                    : String(localized: "No items found", table: "NotchcastCleaner"))
            } else {
                CleanerReviewView(
                    rows: rows, selected: selected, checked: checked, scroll: scroll, onCheck: onCheck,
                    onSelect: onSelect)
            }
            if hasItems {
                Text(selectionSummary)
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, metrics.spacing.xl)
                    .padding(.vertical, metrics.spacing.md)
            }
        }
    }

    private var selectionSummary: String {
        let size = MeasuredSize(bytes: bytes).formatted
        if hiddenCount > 0 {
            return String(localized: "\(checked.count) selected · \(size) · \(hiddenCount) hidden",
                          table: "NotchcastCleaner")
        }
        return String(localized: "\(checked.count) selected · \(size)", table: "NotchcastCleaner")
    }
}

private struct CleanerActivityView: View {
    @Environment(\.metrics) private var metrics
    let text: String
    let count: Int?

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text(text)
                .font(metrics.typography.rowTitle)
            if let count, count > 0 {
                Text("\(count) found", tableName: "NotchcastCleaner")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
