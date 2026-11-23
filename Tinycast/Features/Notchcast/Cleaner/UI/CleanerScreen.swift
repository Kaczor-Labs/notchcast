import SwiftUI

struct CleanerScreen: PaletteScreen {
    let module: CleanerModule
    let palette: PaletteState

    private var session: CleanerSession { module.session }

    var rows: [CleanerItem] {
        guard session.phase == .review || session.phase == .confirming else { return [] }
        let query = palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = session.items.filter {
            query.isEmpty || $0.id.lastPathComponent.localizedStandardContains(query)
        }
        let groups = Dictionary(grouping: matches, by: \.area.kind)
        return CleanerArea.Kind.allCases.flatMap { groups[$0] ?? [] }
    }

    var hidesSearchField: Bool { session.phase != .review && session.phase != .confirming }
    var actsWithoutRows: Bool { true }

    var primaryActionTitle: String {
        switch session.phase {
        case .needsAccess: String(localized: "Open System Settings…", table: "NotchcastCleaner")
        case .scanFailed, .done: String(localized: "Scan Again", table: "NotchcastCleaner")
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
        case .scanFailed, .done: module.scan()
        case .review: module.clean()
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
        module.scan()
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
        if rows.isEmpty {
            EmptyResults(text: session.items.isEmpty
                ? String(localized: "No items found", table: "NotchcastCleaner")
                : String(localized: "No matching items", table: "NotchcastCleaner"))
        } else {
            CleanerReviewLayout(
                rows: rows, selected: rows.indices.contains(selection) ? rows[selection] : nil,
                checked: session.selection?.checked ?? [], bytes: session.selectedBytes, scroll: scroll,
                onSelect: { id in
                    if let index = rows.firstIndex(where: { $0.id == id }) { palette.selection = index }
                },
                onCheck: toggle)
        }
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
    let bytes: Int64
    let scroll: ScrollIntent
    let onSelect: (CleanerItem.ID) -> Void
    let onCheck: (CleanerItem.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CleanerReviewView(rows: rows, selected: selected, checked: checked, scroll: scroll,
                              onSelect: onSelect, onCheck: onCheck)
            Text("\(checked.count) selected · \(MeasuredSize(bytes: bytes).formatted)", tableName: "NotchcastCleaner")
                .font(metrics.typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
        }
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
