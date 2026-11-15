import SwiftUI
import UniformTypeIdentifiers

struct QuitProtectionSettingsView: View {
    /// Seeded once: the module re-reads the same suite, so this store is the pane's only writer.
    @State private var store: QuitProtectionStore

    init(defaults: UserDefaults) {
        _store = State(initialValue: QuitProtectionStore(defaults: defaults))
    }

    var body: some View {
        Picker(selection: $store.configuration.mode) {
            Text("Holding ⌘Q", tableName: "NotchcastQuitProtection").tag(QuitProtectionEngine.Mode.hold)
            Text("Pressing ⌘Q twice", tableName: "NotchcastQuitProtection")
                .tag(QuitProtectionEngine.Mode.doublePress)
        } label: {
            Text("Confirm by", tableName: "NotchcastQuitProtection")
        }
        Toggle(isOn: $store.configuration.closeEnabled) {
            Text("Protect ⌘W", tableName: "NotchcastQuitProtection")
            Text("Same confirmation before closing a window.", tableName: "NotchcastQuitProtection")
        }
        Text("These apps quit and close without asking.", tableName: "NotchcastQuitProtection")
        if store.configuration.exceptions.isEmpty {
            Text("Nothing here yet.").foregroundStyle(.secondary)
        }
        ForEach(store.configuration.exceptions.sorted(), id: \.self) { identifier in
            QuitProtectionExceptionRow(identifier: identifier) {
                store.configuration.exceptions.remove(identifier)
            }
        }
        Button(action: addApplications) {
            Text("Add app…", tableName: "NotchcastQuitProtection")
        }
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        store.configuration.exceptions.formUnion(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}
