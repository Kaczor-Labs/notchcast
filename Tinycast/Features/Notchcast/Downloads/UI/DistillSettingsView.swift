import SwiftUI

struct DistillSettingsView: View {
    @AppStorage private var folder: String?
    @AppStorage private var convertDrops: Bool
    private static let anchor = NotchcastSettingsSearch.anchor(.filesDownloads)
    private static let convertHelp = LocalizedStringResource(
        "PDF, HTML, audio and video files added to the Markdown folder while this is on become notes. Originals go to the Trash.",
        table: "NotchcastDownloads")

    init(defaults: UserDefaults) {
        _folder = AppStorage(DistillNotes.folderKey, store: defaults)
        _convertDrops = AppStorage(wrappedValue: false, DistillNotes.convertKey, store: defaults)
    }

    var body: some View {
        LabeledContent {
            HStack {
                if folder != nil {
                    Button {
                        folder = nil
                    } label: {
                        Text("Clear", tableName: "NotchcastDownloads")
                    }
                }
                Button(action: chooseFolder) {
                    Text("Choose…", tableName: "NotchcastDownloads")
                }
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Markdown folder", table: "NotchcastDownloads"))
            if let folder {
                Text(folder)
            } else {
                Text("Choose a folder to also save everything Distill makes there as a Markdown note.",
                     tableName: "NotchcastDownloads")
            }
        }
        Toggle(isOn: $convertDrops) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Convert dropped files", table: "NotchcastDownloads"))
            Text(Self.convertHelp)
        }
        .settingsEnabled(folder != nil)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path(percentEncoded: false)
    }
}
