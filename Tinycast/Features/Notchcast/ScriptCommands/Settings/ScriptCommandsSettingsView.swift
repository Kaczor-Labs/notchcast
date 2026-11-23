import SwiftUI

/// The rows under the switch: each one's launcher fields, its editor while open and its last output.
struct ScriptCommandsSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    let context: NotchcastContext
    @State private var editing: String?
    @State private var pendingAdd: String?
    @State private var pendingDeletion: ScriptCommand?
    private static let anchor = NotchcastSettingsSearch.anchor(.launcher)

    var body: some View {
        if let scripts = mainApp.notchcastStatus(for: ScriptCommandsAddon.self) {
            if scripts.rows.isEmpty {
                Text("No script commands yet.", tableName: "NotchcastScriptCommands").foregroundStyle(.secondary)
            }
            ForEach(scripts.rows, id: \.id) { row in
                ScriptCommandRow(
                    row: row, running: scripts.running.contains(row.id), preferences: context.preferences,
                    isEditing: editing == row.id,
                    onEdit: { editing = editing == row.id ? nil : row.id }, onDelete: { pendingDeletion = row })
                if editing == row.id {
                    ScriptCommandEditor(row: row)
                }
                if let revision = scripts.outputRevisions[row.id] {
                    ScriptCommandOutput(id: row.id, name: row.title, revision: revision)
                }
            }
            Button {
                guard pendingAdd == nil else { return }
                let id = UUID().uuidString
                pendingAdd = id
                mainApp.sendNotchcast(.addScript(id), to: ScriptCommandsAddon.self)
            } label: {
                SettingsRowTitle(Self.anchor, LocalizedStringResource("Add Script Command", table: "NotchcastScriptCommands"))
            }
            .settingsEnabled(pendingAdd == nil)
            .onChange(of: scripts.rows.map(\.id)) { _, ids in
                guard let id = pendingAdd, ids.contains(id) else { return }
                pendingAdd = nil
                editing = id
            }
            .onDisappear { pendingAdd = nil }
            .confirmationDialog(
                pendingDeletion.map {
                    String(localized: "Delete “\($0.title)”?", table: "NotchcastScriptCommands")
                } ?? "",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { row in
                Button(role: .destructive) {
                    if editing == row.id { editing = nil }
                    mainApp.sendNotchcast(.deleteScript(row.id), to: ScriptCommandsAddon.self)
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

    // Not SettingsRow: its one-line title truncates beside the row's controls.
    var body: some View {
        let shown = preferences.showsInLauncher(entryID)
        NotchcastCommandRow {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: ScriptCommandsModule.symbol)
                    .fixedSize()
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(name)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(shown ? 1 : 0.45)
                    if !row.script.isEmpty {
                        Text(row.script)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.script)
                    }
                }
                .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
            }
        } trailing: {
            if running {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "\(name) is running", table: "NotchcastScriptCommands"))
            }
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
        } fields: {
            Group {
                AliasField(key: entryID, name: name)
                    .settingsEnabled(shown)
                ShortcutRecorder(action: .notchcastCommand(entryID: entryID))
            }
            .settingsEnabled(row.isRunnable)
        } checkbox: {
            Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(entryID, $0) })) {
                Text("Show in launcher", tableName: "NotchcastScriptCommands")
            }
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel(String(localized: "Show \(name) in the launcher", table: "NotchcastScriptCommands"))
            .settingsEnabled(row.isRunnable)
        }
    }
}
