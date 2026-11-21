import SwiftUI

struct NotchcastSettingsView: View {
    let controller: NotchcastController
    let pane: NotchcastPane

    private var preferences: NotchcastPreferences { controller.preferences }

    var body: some View {
        let commands = Dictionary(grouping: controller.slots.flatMap { $0.addon.commands }, by: \.switchID)
        let rows = Dictionary(grouping: controller.slots.flatMap(\.settings), by: \.row.switchID)
        let groups = NotchcastSettingsLayout(switches: controller.switches).groups(
            in: pane, isEnabled: preferences.isEnabled, withCommands: Set(commands.keys), withRows: Set(rows.keys))
        Form {
            if pane == .island {
                NotchcastIslandSettingsRows()
                NotchcastLookSection(looks: AppCore.shared.island.looks)
            }
            ForEach(groups) { group in
                let anchor = NotchcastSettingsSearch.anchor(group.category)
                Section {
                    ForEach(group.switches) { item in
                        switchRows(item, anchor: anchor)
                    }
                } header: {
                    SettingsSectionHeader(anchor)
                }
                ForEach(group.details) { detail in
                    if detail.hasOptions {
                        options(detail, anchor: anchor, rows: rows[detail.id, default: []])
                    }
                    if detail.hasCommands {
                        commandSection(detail.item, commands: commands[detail.id, default: []])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast(pane))
        .onAppear { controller.hub.refreshPermission() }
    }

    private func options(
        _ detail: NotchcastSettingsLayout.Detail, anchor: SettingsAnchor, rows: [NotchcastController.SettingsEntry]
    ) -> some View {
        Section {
            ForEach(detail.dependents) { item in
                switchRows(item, anchor: anchor)
            }
            if detail.hasRows, let context = controller.context(forSwitch: detail.id) {
                ForEach(rows) { entry in
                    entry.row.view(context)
                }
            }
        } header: {
            Text("\(detail.item.title) Options", tableName: "Notchcast")
        }
    }

    private func commandSection(_ item: NotchcastSwitch, commands: [NotchcastCommand]) -> some View {
        Section {
            ForEach(commands) { command in
                let shown = preferences.showsInLauncher(command.id)
                NotchcastCommandRow {
                    Text(command.name)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
                        .opacity(shown ? 1 : 0.45)
                } trailing: {
                    EmptyView()
                } controls: {
                    AliasField(key: command.id, name: command.name)
                    ShortcutRecorder(action: .notchcastCommand(entryID: command.id))
                    Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(command.id, $0) })) {
                        NotchcastLauncherCheckboxLabel(title: Text("Show in launcher"))
                    }
                        .toggleStyle(.checkbox)
                        .launcherVisibilityHelp()
                        .accessibilityLabel(
                            String(localized: "Show \(command.name) in the launcher", table: "Notchcast"))
                }
            }
        } header: {
            Text("\(item.title) Commands", tableName: "Notchcast")
        }
    }

    @ViewBuilder
    private func switchRows(_ item: NotchcastSwitch, anchor: SettingsAnchor) -> some View {
        Toggle(isOn: Binding(get: { preferences.isOn(item.id) }, set: { preferences.set(item.id, on: $0) })) {
            SettingsRowTitle(anchor, verbatim: item.title)
            if !item.subtitle.isEmpty { Text(item.subtitle) }
        }
        if preferences.isEnabled(item.id), item.requiredGrants.contains(.accessibility), !controller.hub.isTrusted {
            LabeledContent {
                Button("Grant Access…") { Permissions.openAccessibilitySettings() }
            } label: {
                Label(
                    String(localized: "Needs Accessibility access", table: "Notchcast"),
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
    }
}
