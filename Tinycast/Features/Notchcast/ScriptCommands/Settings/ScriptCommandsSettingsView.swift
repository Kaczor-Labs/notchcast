import SwiftUI

/// The rows under the switch: each one's launcher fields, its editor while open and its last output.
struct ScriptCommandsSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    let context: NotchcastContext
    @State private var editing: String?
    @State private var pendingDeletion: ScriptCommand?
    private static let anchor = NotchcastSettingsSearch.anchor(.launcher)

    var body: some View {
        if let scripts = mainApp.status.notchcast.scripts {
            if scripts.rows.isEmpty {
                Text("No script commands yet.", tableName: "NotchcastScriptCommands").foregroundStyle(.secondary)
            }
            ForEach(scripts.rows) { row in
                ScriptCommandRow(
                    row: row, running: scripts.running.contains(row.id), preferences: context.preferences,
                    isEditing: editing == row.id,
                    onEdit: { editing = editing == row.id ? nil : row.id }, onDelete: { pendingDeletion = row })
                if editing == row.id {
                    ScriptCommandEditor(row: row).id(row.id)
                }
                if let revision = scripts.outputRevisions[row.id] {
                    ScriptCommandOutput(id: row.id, name: row.title, revision: revision)
                }
            }
            Button {
                let id = UUID().uuidString
                mainApp.send(.notchcast(.addScript(id)))
                editing = id
            } label: {
                SettingsRowTitle(Self.anchor, LocalizedStringResource("Add Script Command", table: "NotchcastScriptCommands"))
            }
            .confirmationDialog(
                pendingDeletion.map {
                    String(localized: "Delete “\($0.title)”?", table: "NotchcastScriptCommands")
                } ?? "",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { row in
                Button(role: .destructive) {
                    if editing == row.id { editing = nil }
                    mainApp.send(.notchcast(.deleteScript(row.id)))
                } label: {
                    Text("Delete", tableName: "NotchcastScriptCommands")
                }
            } message: { _ in
                Text("Its alias and shortcut go with it.", tableName: "NotchcastScriptCommands")
            }
        }
    }
}

/// One row as the launcher sees it: name and script, then alias, shortcut and launcher checkbox.
private struct ScriptCommandRow: View {
    let row: ScriptCommand
    let running: Bool
    let preferences: NotchcastPreferences
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var entryID: String { NotchcastCommand.idPrefix + row.slug }
    private var name: String {
        row.title.isEmpty ? String(localized: "Untitled", table: "NotchcastScriptCommands") : row.title
    }

    var body: some View {
        let shown = preferences.showsInLauncher(entryID)
        SettingsRow(title: name, subtitle: row.script.isEmpty ? nil : row.script) {
            Image(systemName: ScriptCommandsModule.symbol)
        } trailing: {
            if running {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "\(name) is running", table: "NotchcastScriptCommands"))
            }
            Group {
                AliasField(key: entryID, name: name)
                    .settingsEnabled(shown)
                ShortcutRecorder(action: .notchcastCommand(entryID: entryID))
                Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(entryID, $0) })) {
                    Text("Show in launcher", tableName: "NotchcastScriptCommands")
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(String(localized: "Show \(name) in the launcher", table: "NotchcastScriptCommands"))
            }
            .settingsEnabled(row.isRunnable)
            Button(action: onEdit) {
                Image(systemName: isEditing ? "chevron.up" : "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Edit \(name)", table: "NotchcastScriptCommands"))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Delete \(name)", table: "NotchcastScriptCommands"))
        }
    }
}
