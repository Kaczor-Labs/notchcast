import SwiftUI
import UniformTypeIdentifiers

struct QuitProtectionSettingsView: View {
    /// Seeded once: the module re-reads the same suite, so this store is the pane's only writer.
    @State private var store: QuitProtectionStore
    private static let anchor = NotchcastSettingsSearch.anchor(.keyboardMouse)

    init(defaults: UserDefaults) {
        _store = State(initialValue: QuitProtectionStore(defaults: defaults))
    }

    var body: some View {
        Picker(selection: $store.configuration.mode) {
            Text("Holding ⌘Q", tableName: "NotchcastQuitProtection").tag(QuitProtectionEngine.Mode.hold)
            Text("Pressing ⌘Q twice", tableName: "NotchcastQuitProtection")
                .tag(QuitProtectionEngine.Mode.doublePress)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Confirm by", table: "NotchcastQuitProtection"))
            Text("How you confirm a quit or a close.", tableName: "NotchcastQuitProtection")
        }
        Toggle(isOn: $store.configuration.closeEnabled) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Protect ⌘W", table: "NotchcastQuitProtection"))
            Text("Same confirmation before closing a window.", tableName: "NotchcastQuitProtection")
        }
        LabeledContent {
            EmptyView()
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Exceptions", table: "NotchcastQuitProtection"))
            Text("These apps quit and close without asking.", tableName: "NotchcastQuitProtection")
        }
        if store.configuration.exceptions.isEmpty {
            Text("Nothing here yet.", tableName: "NotchcastQuitProtection").foregroundStyle(.secondary)
        }
        ForEach(store.configuration.exceptions.sorted(), id: \.self) { identifier in
            QuitProtectionExceptionRow(identifier: identifier) {
                store.configuration.exceptions.remove(identifier)
            }
        }
        Button(action: addApplications) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Add App…", table: "NotchcastQuitProtection"))
        }
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Add", table: "NotchcastQuitProtection")
        guard panel.runModal() == .OK else { return }
        store.configuration.exceptions.formUnion(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}
