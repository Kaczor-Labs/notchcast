import SwiftUI

struct DistillSettingsView: View {
    @AppStorage private var folder: String?
    @AppStorage private var convertDrops: Bool
    private static let anchor = NotchcastSettingsSearch.anchor(.downloads)
    private static let convertHelp = LocalizedStringResource(
        "When you put a PDF, web page, audio or video file in your Markdown folder, Notchcast saves it as a Markdown note and moves the original to the Trash. Files already there stay as they are.",
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
        if folder != nil {
            notchcastSettingsToggle(
                SettingsRowTitle(Self.anchor, LocalizedStringResource(
                    "Turn files in the Markdown folder into notes", table: "NotchcastDownloads")),
                isOn: $convertDrops
            ) {
                Text(Self.convertHelp)
            }
        }
        DistillQueueView()
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
