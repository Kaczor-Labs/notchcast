import SwiftUI

struct MacTweaksSettingsView: View {
    enum Page { case catalogue, finder }

    let page: Page
    @Environment(MainAppLink.self) private var mainApp
    @Environment(\.openNotchcastSettingsSubpage) private var openSubpage
    @State private var state = MacTweaksPageState()
    @State private var request: MacTweaksAddon.Request? = .snapshot
    @State private var confirmsUndo = false

    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    var body: some View {
        switch page {
        case .catalogue:
            Button { openSubpage?(MacTweaksAddon.finderPage) } label: {
                LabeledContent {
                    if let snapshot = state.snapshot {
                        let applied = snapshot.applied
                        let count = MacTweakCatalog.finder.count { applied.contains($0.id) }
                        Text("\(count) of \(MacTweakCatalog.finder.count) on", tableName: "NotchcastMacTweaks")
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                } label: {
                    SettingsRowTitle(Self.anchor, LocalizedStringResource("Finder", table: "NotchcastMacTweaks"))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(request != nil || openSubpage == nil)
            Button(role: .destructive) { confirmsUndo = true } label: {
                Text("Undo Everything…", tableName: "NotchcastMacTweaks")
            }
            .disabled(request != nil || state.snapshot?.journaled.isEmpty != false)
            .confirmationDialog(
                Text("Restore all changed settings?", tableName: "NotchcastMacTweaks"), isPresented: $confirmsUndo
            ) {
                Button(role: .destructive) { request = .undoEverything } label: {
                    Text("Undo Everything", tableName: "NotchcastMacTweaks")
                }
            } message: {
                Text("Restore the settings Notchcast changed. Finder may restart.", tableName: "NotchcastMacTweaks")
            }
            .task(id: request) { await runRequest() }
            if request != nil {
                progressLine
            } else {
                noticeRow
            }
        case .finder:
            Form {
                Section {
                    ForEach(MacTweakCatalog.finder) { tweak in
                        finderRow(tweak)
                    }
                } header: {
                    if request == nil { noticeRow }
                } footer: {
                    Text("Most of these restart Finder, which may interrupt file copies.", tableName: "NotchcastMacTweaks")
                }
            }
            .formStyle(.grouped)
            .task(id: request) { await runRequest() }
        }
    }

    @ViewBuilder
    private var noticeRow: some View {
        if let notice = state.notice {
            LabeledContent {
                Button { request = .snapshot } label: { Text("Refresh", tableName: "NotchcastMacTweaks") }
            } label: {
                Text(notice)
            }
        }
    }

    private var progressLine: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            if request == .snapshot {
                Text("Reading settings…", tableName: "NotchcastMacTweaks")
            } else {
                Text("Changing settings…", tableName: "NotchcastMacTweaks")
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func finderRow(_ tweak: MacTweak) -> some View {
        let tweakState = state.snapshot?.states[tweak.id]
        let title = SettingsRowTitle(Self.anchor, tweak.finderTitle)
        if let tweakState, let explanation = tweakState.unavailableReason {
            LabeledContent {
                Text(explanation)
            } label: {
                title
            }
        } else if case .set(tweak.id, _) = request {
            LabeledContent {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(Text("Changing settings…", tableName: "NotchcastMacTweaks"))
            } label: {
                title
                rowDetail(tweak, state: tweakState)
            }
        } else {
            notchcastSettingsToggle(title, isOn: Binding(
                get: { tweakState == .applied }, set: { request = .set(tweak.id, $0) }
            )) {
                rowDetail(tweak, state: tweakState)
            }
            .disabled(request != nil || tweakState == nil)
        }
    }

    @ViewBuilder
    private func rowDetail(_ tweak: MacTweak, state: MacTweakState?) -> some View {
        if state == .partial {
            Text("Partly applied", tableName: "NotchcastMacTweaks")
        } else if let detail = tweak.finderDetail {
            Text(detail)
        }
    }

    private func runRequest() async {
        guard let request else { return }
        state.clearNotice()
        do {
            let reply = try await mainApp.callNotchcast(request, to: MacTweaksAddon.self)
            try Task.checkCancellation()
            state.received(reply.snapshot, notice: reply.notice)
        } catch where Task.isCancelled {
            if error is CancellationError, request != .snapshot { self.request = .snapshot }
            return
        } catch {
            // A refusal from the main app (switch not yet on there, no store) arrives as CancellationError.
            state.failed(request == .snapshot ? .read : .change)
        }
        self.request = nil
    }
}
