import SwiftUI

/// The Notchcast pane: one section per category, generated from the descriptors.
struct NotchcastSettingsView: View {
    let controller: NotchcastController

    var body: some View {
        Form {
            ForEach(NotchcastCategory.allCases, id: \.self) { category in
                let switches = controller.switches.filter { $0.category == category }
                if !switches.isEmpty {
                    let anchor = NotchcastSettingsSearch.anchor(category)
                    Section {
                        ForEach(switches) { item in
                            NotchcastSwitchRows(controller: controller, item: item, anchor: anchor)
                        }
                    } header: {
                        SettingsSectionHeader(anchor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast)
        .onAppear { controller.hub.refreshPermission() }
    }
}

/// A switch, then its commands' shortcut recorders and its extra rows while it is on.
private struct NotchcastSwitchRows: View {
    let controller: NotchcastController
    let item: NotchcastSwitch
    let anchor: SettingsAnchor

    private var preferences: NotchcastPreferences { controller.preferences }

    private var dependenciesMet: Bool { item.dependencies.allSatisfy(preferences.isEnabled) }

    private var needsAccessibility: Bool {
        item.requiredGrants.contains(.accessibility) && !controller.hub.isTrusted
    }

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(item.id) }, set: { preferences.set(item.id, on: $0) })) {
            SettingsRowTitle(anchor, verbatim: item.title)
            Text(item.subtitle)
        }
        .settingsEnabled(dependenciesMet)
        if preferences.isEnabled(item.id), needsAccessibility {
            LabeledContent {
                Button(String(localized: "Grant access…", table: "Notchcast")) { Permissions.openAccessibilitySettings() }
            } label: {
                Label(String(localized: "Needs Accessibility access", table: "Notchcast"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
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
