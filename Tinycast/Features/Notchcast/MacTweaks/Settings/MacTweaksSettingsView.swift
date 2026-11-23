import SwiftUI

struct MacTweaksSettingsView: View {
    @State private var snapshot: MacTweakSnapshot?

    var body: some View {
        MacTweaksPage(page: .catalogue, snapshot: $snapshot)
    }
}

private struct MacTweaksPage: View {
    enum Page { case catalogue, finder }

    let page: Page
    @Binding var snapshot: MacTweakSnapshot?
    @Environment(MainAppLink.self) private var mainApp
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var request: MacTweaksAddon.Request? = .snapshot
    @State private var notice: String?
    @State private var confirmsUndo = false

    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    var body: some View {
        switch page {
        case .catalogue:
            NavigationLink {
                MacTweaksPage(page: .finder, snapshot: $snapshot)
            } label: {
                LabeledContent {
                    if let snapshot {
                        let applied = snapshot.applied
                        let count = MacTweakCatalog.finder.count { applied.contains($0.id) }
                        Text("\(count) of \(MacTweakCatalog.finder.count) on", tableName: "NotchcastMacTweaks")
                    }
                } label: {
                    SettingsRowTitle(Self.anchor, LocalizedStringResource("Finder", table: "NotchcastMacTweaks"))
                }
            }
            .disabled(request != nil)
            Button(role: .destructive) { confirmsUndo = true } label: {
                Text("Undo Everything…", tableName: "NotchcastMacTweaks")
            }
            .disabled(request != nil || snapshot?.journaled.isEmpty != false)
            .confirmationDialog(
                Text("Restore all changed settings?", tableName: "NotchcastMacTweaks"), isPresented: $confirmsUndo
            ) {
                Button(role: .destructive) { request = .undoEverything } label: {
                    Text("Undo Everything", tableName: "NotchcastMacTweaks")
                }
            } message: {
                Text("Restore the settings Notchcast changed. Finder may restart.", tableName: "NotchcastMacTweaks")
            }
            .onAppear { if request == nil { request = .snapshot } }
            .task(id: request) { await runRequest() }
            feedback()
        case .finder:
            Form {
                Section {
                    ForEach(MacTweakCatalog.finder) { tweak in
                        finderRow(tweak)
                    }
                } header: {
                    feedback(reservesSpace: true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Mac Tweaks – Finder", table: "NotchcastMacTweaks"))
            .onChange(of: navigation.tab) { _, tab in
                if tab != .notchcast(.macTweaks) { dismiss() }
            }
            .task(id: request) { await runRequest() }
        }
    }

    @ViewBuilder
    private func feedback(reservesSpace: Bool = false) -> some View {
        if request == nil, let notice {
            LabeledContent {
                Button { request = .snapshot } label: { Text("Refresh", tableName: "NotchcastMacTweaks") }
            } label: {
                Text(notice)
            }
        } else if request != nil || reservesSpace {
            ProgressView {
                if request == .snapshot {
                    Text("Reading settings…", tableName: "NotchcastMacTweaks")
                } else {
                    Text("Changing settings…", tableName: "NotchcastMacTweaks")
                }
            }
            .opacity(request == nil ? 0 : 1)
            .accessibilityHidden(request == nil)
        }
    }

    @ViewBuilder
    private func finderRow(_ tweak: MacTweak) -> some View {
        let state = snapshot?.states[tweak.id]
        let title = SettingsRowTitle(Self.anchor, tweak.finderTitle)
        if let state, let explanation = state.unavailableReason {
            LabeledContent {
                Text(explanation)
            } label: {
                title
            }
        } else {
            notchcastSettingsToggle(title, isOn: Binding(
                get: { state == .applied }, set: { request = .set(tweak.id, $0) }
            )) {
                if state == .partial {
                    Text("Partly applied", tableName: "NotchcastMacTweaks")
                } else if tweak.restarts.contains(.finder) {
                    Text("Restarts Finder and may interrupt file copies.", tableName: "NotchcastMacTweaks")
                } else if let detail = tweak.finderDetail {
                    Text(detail)
                }
            }
            .disabled(request != nil || state == nil)
        }
    }

    private func runRequest() async {
        guard let request else { return }
        notice = nil
        do {
            let reply = try await mainApp.callNotchcast(request, to: MacTweaksAddon.self)
            try Task.checkCancellation()
            snapshot = reply.snapshot
            notice = reply.notice
        } catch is CancellationError {
            if Task.isCancelled {
                if request != .snapshot { self.request = .snapshot }
                return
            }
        } catch {
            guard !Task.isCancelled else { return }
            snapshot = nil
            if request == .snapshot {
                notice = String(localized: "Couldn’t read Mac Tweaks. Refresh to try again.", table: "NotchcastMacTweaks")
            } else {
                notice = String(
                    localized: "Couldn’t finish the change. Refresh to check your settings.", table: "NotchcastMacTweaks")
            }
        }
        self.request = nil
    }
}
