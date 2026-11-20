import AppKit
import SwiftUI

/// The folder, how many backups stay, and every backup in the folder with the stock import behind Restore.
struct AutoBackupSettingsView: View {
    let context: NotchcastContext
    @State private var chosenFolder: String?
    @State private var keep = AutoBackupSchedule.defaultKeep
    @State private var backups: [URL] = []
    @State private var restoring: URL?
    /// Changes with every backup the module writes, so the list refreshes while the pane is open.
    @State private var schedule: Data?
    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    private var preferences: AutoBackupPreferences { AutoBackupPreferences(defaults: context.defaults) }

    private struct Listing: Equatable {
        let folder: String?
        let schedule: Data?
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button { chooseFolder() } label: { Text("Choose…", tableName: "NotchcastAutoBackup") }
                Button { reveal() } label: { Text("Show in Finder", tableName: "NotchcastAutoBackup") }
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Backup folder", table: "NotchcastAutoBackup"))
            Text(verbatim: (preferences.folder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
        }
        .confirmationDialog(
            Text("Restore settings from this backup?", tableName: "NotchcastAutoBackup"),
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            presenting: restoring
        ) { file in
            Button(String(localized: "Cancel"), role: .cancel) { restoring = nil }
            Button { Task { await context.settingsBackup.restore(file) } } label: {
                Text("Restore", tableName: "NotchcastAutoBackup")
            }
        } message: { file in
            Text(
                "Settings saved in \(file.deletingPathExtension().lastPathComponent) replace the current ones.",
                tableName: "NotchcastAutoBackup")
        }
        .task(id: Listing(folder: chosenFolder, schedule: schedule)) { await reload() }
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: context.defaults)
        ) { _ in readSchedule() }
        .onAppear {
            readSchedule()
            chosenFolder = preferences.chosenFolder
            keep = preferences.keep
        }
        .onChange(of: keep) { preferences.keep = keep }
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: "\(keep)").monospacedDigit().foregroundStyle(.secondary)
                Stepper(value: $keep, in: AutoBackupSchedule.keepRange) {
                    Text("Backups to keep", tableName: "NotchcastAutoBackup")
                }
                .labelsHidden()
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Backups to keep", table: "NotchcastAutoBackup"))
            Text("The oldest backup this Mac wrote goes first.", tableName: "NotchcastAutoBackup")
        }
        if backups.isEmpty {
            Text("No backups yet", tableName: "NotchcastAutoBackup").foregroundStyle(.secondary)
        }
        ForEach(backups, id: \.self) { file in
            LabeledContent {
                Button { restoring = file } label: { Text("Restore…", tableName: "NotchcastAutoBackup") }
                    .accessibilityLabel(
                        Text("Restore \(file.deletingPathExtension().lastPathComponent)", tableName: "NotchcastAutoBackup"))
            } label: {
                Text(verbatim: file.deletingPathExtension().lastPathComponent)
            }
        }
    }

    private func readSchedule() {
        schedule = context.defaults.data(forKey: AutoBackupPreferences.scheduleKey)
    }

    private func reload() async {
        backups = await Self.list(preferences.folder)
    }

    /// Every backup in the folder, newest first, other Macs' included; listing a synced folder can stall.
    @concurrent private static func list(_ folder: URL) async -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        let dated = files.filter { $0.pathExtension == AutoBackupSchedule.fileExtension }.map { file in
            (file, (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.chosenFolder = url.path(percentEncoded: false)
        chosenFolder = preferences.chosenFolder
    }

    private func reveal() {
        let folder = preferences.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        AppLauncher.showInFinder(folder)
    }
}
