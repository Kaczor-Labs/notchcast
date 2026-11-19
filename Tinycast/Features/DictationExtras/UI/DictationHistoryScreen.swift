import SwiftUI

/// Past dictations, newest first: ↵ pastes the text again, ⌘↵ copies it, ⌘K offers the raw one.
struct DictationHistoryScreen: PaletteScreen {
    let coordinator: DictationExtrasCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [DictationHistoryEntry] { coordinator.history.search(vm.query) }

    var primaryActionTitle: String { String(localized: "Paste Again", table: "Notchcast") }

    private func entry(at selection: Int) -> DictationHistoryEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        entry(at: selection).map { DictationHistoryActionsMenu.content(entry: $0, coordinator: coordinator) }
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        coordinator.paste(entry.text)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.copy(entry.text)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            guard let entry = entry(at: selection) else { return false }
            coordinator.history.remove(entry)
            return true
        case .deleteAll:
            Task { await coordinator.clearHistory() }
            return true
        default: return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        guard !rows.isEmpty else {
            return AnyView(
                EmptyResults(
                    text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                        ? String(localized: "No dictations yet", table: "Notchcast")
                        : String(localized: "No matching dictations", table: "Notchcast"),
                    systemImage: CommandID.dictationHistory.sfSymbol))
        }
        return AnyView(
            DictationHistoryList(
                entries: rows, selectedID: entry(at: selection)?.id, scroll: scroll,
                onSelect: { entry in
                    if let index = rows.firstIndex(of: entry) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { entry in
                    if let index = rows.firstIndex(of: entry) { vm.selection = index }
                    openActions()
                }))
    }
}

@MainActor
enum DictationHistoryActionsMenu {
    static func content(
        entry: DictationHistoryEntry, coordinator: DictationExtrasCoordinator
    ) -> PopoverMenuContent {
        var items = [
            PopoverMenuItem(
                title: String(localized: "Paste Again", table: "Notchcast"), systemImage: "doc.on.clipboard",
                shortcut: "↵"
            ) { coordinator.paste(entry.text) },
            PopoverMenuItem(
                title: String(localized: "Copy Text"), systemImage: "doc.on.doc", shortcut: "⌘↵"
            ) { coordinator.copy(entry.text) }
        ]
        if entry.cleaned != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Raw Transcript", table: "Notchcast"),
                    systemImage: "waveform"
                ) { coordinator.copy(entry.raw) })
        }
        items += [
            PopoverMenuItem(
                title: String(localized: "Delete Entry"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) { coordinator.history.remove(entry) },
            PopoverMenuItem(
                title: String(localized: "Delete All Entries"), systemImage: "trash", shortcut: "⌃⇧X",
                isDestructive: true
            ) { Task { await coordinator.clearHistory() } }
        ]
        return PopoverMenuContent(header: entry.text, items: items)
    }
}

/// Shaped like `CalculatorHistoryList`: date headers, one line per dictation.
private struct DictationHistoryList: View {
    @Environment(\.metrics) private var metrics
    let entries: [DictationHistoryEntry]
    let selectedID: DictationHistoryEntry.ID?
    let scroll: ScrollIntent
    let onSelect: (DictationHistoryEntry) -> Void
    let onActivate: () -> Void
    let onActions: (DictationHistoryEntry) -> Void

    private enum Row: Identifiable {
        case header(String)
        case entry(DictationHistoryEntry)

        var id: String {
            switch self {
            case .header(let title): "header-" + title
            case .entry(let entry): entry.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var bucket: DateBucket?
        for entry in entries {
            let current = DateBucket(for: entry.createdAt)
            if current != bucket {
                rows.append(.header(current.title))
                bucket = current
            }
            rows.append(.entry(entry))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .entry(let entry):
                            DictationHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .selectionFrame(entry.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(entry) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(entry)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(entry) }
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString,
                atOrigin: selectedID != nil && selectedID == entries.first?.id, proxy: proxy)
        }
    }
}

private struct DictationHistoryRow: View {
    @Environment(\.metrics) private var metrics
    let entry: DictationHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var detail: String {
        let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
        guard let app = entry.app else { return time }
        return app + " · " + time
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            IconTile(
                symbol: CommandID.dictationHistory.sfSymbol, tint: CommandID.dictationHistory.tint,
                extent: IconCache.appIconBody
            )
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(entry.text)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: metrics.spacing.xl)
            Text(detail)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
    }
}
