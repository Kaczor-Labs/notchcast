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
