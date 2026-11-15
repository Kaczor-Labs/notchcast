import SwiftUI

/// The Notchcast pane: one section per category, generated from the descriptors.
struct NotchcastSettingsView: View {
    let controller: NotchcastController

    var body: some View {
        Form {
            ForEach(NotchcastCategory.allCases, id: \.self) { category in
                let switches = controller.switches.filter { $0.category == category }
                if !switches.isEmpty {
                    Section(category.title) {
                        ForEach(switches) { item in
                            NotchcastSwitchRows(controller: controller, item: item)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A switch, then its commands' shortcut recorders and its extra rows while it is on.
private struct NotchcastSwitchRows: View {
    let controller: NotchcastController
    let item: NotchcastSwitch

    private var preferences: NotchcastPreferences { controller.preferences }

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(item.id) }, set: { preferences.set(item.id, on: $0) })) {
            Text(item.title)
            Text(item.subtitle)
        }
        if preferences.isEnabled(item.id) {
            ForEach(controller.slots.flatMap { $0.addon.commands }.filter { $0.switchID == item.id }) { command in
                SettingsRow(title: command.name) {
                    ShortcutRecorder(action: .notchcastCommand(entryID: command.id))
                }
            }
            if let context = controller.context(forSwitch: item.id) {
                let rows = controller.slots.flatMap { $0.addon.settings }.filter { $0.switchID == item.id }
                ForEach(rows.indices, id: \.self) { index in
                    rows[index].view(context)
                }
            }
        }
    }
}
