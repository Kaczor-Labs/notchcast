import SwiftUI

struct DistillQueueView: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        if let rows = mainApp.notchcastStatus(for: DownloadsAddon.self)?.distill {
            LabeledContent {
                Button { perform(.run) } label: {
                    Text("Run Distill", tableName: "NotchcastDownloads")
                }
            } label: {
                Text("Distill queue", tableName: "NotchcastDownloads")
                Text(DistillQueueList.countLine(rows))
            }
            if rows.contains(where: { $0.state == .failed }) {
                DistillFailedRow(rows: rows, perform: perform)
            }
            if rows.isEmpty {
                Text("No links in the queue.", tableName: "NotchcastDownloads")
            }
            ForEach(rows) { row in
                DistillQueueRow(row: row, perform: perform)
            }
        }
    }

    private func perform(_ action: DownloadsModule.DistillAction) {
        mainApp.sendNotchcast(.distill(action), to: DownloadsAddon.self)
    }
}

private struct DistillFailedRow: View {
    let rows: [DistillQueueList.Row]
    let perform: (DownloadsModule.DistillAction) -> Void
    @State private var removing: [String]?

    private var failed: [String] { rows.filter { $0.state == .failed }.map(\.id) }

    var body: some View {
        let shared = DistillQueueList.sharedFailure(rows)
        LabeledContent {
            HStack {
                if shared?.needsDictationModel == true {
                    DictationSettingsButton()
                }
                Button { perform(.retryFailed(failed)) } label: {
                    Text("Try All Again", tableName: "NotchcastDownloads")
                }
                .accessibilityLabel(Text("Try all failed links again", tableName: "NotchcastDownloads"))
                Button { removing = failed } label: {
                    Text("Remove All", tableName: "NotchcastDownloads")
                }
                .accessibilityLabel(Text("Remove all failed links", tableName: "NotchcastDownloads"))
            }
        } label: {
            Text(DistillQueueList.failedLine(rows))
            if let shared { Text(DistillQueueList.sharedLine(shared)) }
        }
        .confirmationDialog(
            Text("Remove \(removing?.count ?? 0) failed links?", tableName: "NotchcastDownloads"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { ids in
            Button(String(localized: "Cancel"), role: .cancel) { removing = nil }
            Button(role: .destructive) { perform(.removeFailed(ids)) } label: {
                Text("Remove", tableName: "NotchcastDownloads")
            }
        } message: { _ in
            Text("Saved and waiting links stay.", tableName: "NotchcastDownloads")
        }
    }
}

private struct DictationSettingsButton: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Button { navigation.select(.dictation) } label: {
            Text("Open Dictation Settings", tableName: "NotchcastDownloads")
        }
    }
}

private struct DistillQueueRow: View {
    let row: DistillQueueList.Row
    let perform: (DownloadsModule.DistillAction) -> Void

    var body: some View {
        LabeledContent {
            HStack { buttons }
        } label: {
            Text(row.name)
            Text(row.note)
        }
        .accessibilityRepresentation {
            VStack {
                Text("\(row.name), \(row.note)", tableName: "NotchcastDownloads")
                buttons
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if row.state == .held, row.needsDictationModel {
            DictationSettingsButton()
        }
        if row.canRetry {
            Button { perform(.retry(row.id)) } label: {
                Text("Try Again", tableName: "NotchcastDownloads")
            }
            .accessibilityLabel(Text("Try again: \(row.name)", tableName: "NotchcastDownloads"))
        }
        Button { perform(.remove(row.id)) } label: {
            Text("Remove", tableName: "NotchcastDownloads")
        }
        .accessibilityLabel(Text("Remove \(row.name)", tableName: "NotchcastDownloads"))
    }
}
