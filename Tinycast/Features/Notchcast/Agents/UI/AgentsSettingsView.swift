import SwiftUI

/// Under the switch: where the helper on the agents' side must write its two feed files.
struct AgentsSettingsView: View {
    let folder: URL
    private static let anchor = NotchcastSettingsSearch.anchor(.notices)

    var body: some View {
        LabeledContent {
            Button {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } label: {
                Text("Show in Finder", tableName: "NotchcastAgents")
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Feed folder", table: "NotchcastAgents"))
            Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath).textSelection(.enabled)
        }
    }
}
