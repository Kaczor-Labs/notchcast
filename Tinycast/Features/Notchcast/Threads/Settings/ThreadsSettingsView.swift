import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where t3chad's waits file is, under the Threads page switch; t3chad's own path until the user picks one.
struct ThreadsSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    let context: NotchcastContext
    @State private var waitsFile: String?
    private static let anchor = NotchcastSettingsSearch.anchor(.agents)

    private var preferences: ThreadsPreferences { ThreadsPreferences(defaults: context.defaults) }

    private var shownPath: String {
        waitsFile ?? ThreadsDocument.defaultURL(home: preferences.home).path(percentEncoded: false)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button { chooseFile() } label: { Text("Choose…", tableName: "NotchcastThreads") }
                Button { save(nil) } label: { Text("Use Default", tableName: "NotchcastThreads") }
                    .disabled(waitsFile == nil)
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Waits file", table: "NotchcastThreads"))
            Text("The waits.json file t3chad writes. It is read whenever it changes.", tableName: "NotchcastThreads")
            Text(verbatim: (shownPath as NSString).abbreviatingWithTildeInPath)
        }
        .onAppear { waitsFile = preferences.waitsFile }
        .onChange(of: mainApp.notchcastStatus(for: ThreadsAddon.self), initial: true) { _, latest in
            if let latest { waitsFile = latest.waitsFile }
        }
    }

    /// Every change reaches a running module at once, so the page follows Settings.
    private func save(_ path: String?) {
        waitsFile = path
        preferences.waitsFile = path
        mainApp.sendNotchcast(.reloadThreads, to: ThreadsAddon.self)
    }

    /// t3chad's state folder is hidden, so the panel shows hidden files.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(fileURLWithPath: (shownPath as NSString).expandingTildeInPath).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(url.path(percentEncoded: false))
    }
}
