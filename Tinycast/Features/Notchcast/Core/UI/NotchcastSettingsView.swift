import SwiftUI

/// The Notchcast pane: one section per category, generated from the descriptors.
struct NotchcastSettingsView: View {
    let controller: NotchcastController
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.islandShowsInCaptures) {
                    SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.showsInCaptures)
                    Text("Off hides the island from screenshots, recordings and screen sharing.",
                         tableName: "Notchcast")
                }
                Toggle(isOn: $settings.islandOutlineWhenOpen) {
                    SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.outlineWhenOpen)
                    Text("A faint line around the open island in Dark.", tableName: "Notchcast")
                }
                Picker(selection: $settings.islandPosition) {
                    Text("Top edge", tableName: "Notchcast").tag(IslandPosition.topEdge)
                    Text("Menu bar center", tableName: "Notchcast").tag(IslandPosition.menuBarCenter)
                    Text("Menu bar bottom", tableName: "Notchcast").tag(IslandPosition.menuBarBottom)
                } label: {
                    SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.position)
                    Text("A notch always decides where the island sits.", tableName: "Notchcast")
                }
            } header: {
                SettingsSectionHeader(NotchcastSettingsSearch.island)
            }
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
                Label(
                    String(localized: "Needs Accessibility access", table: "Notchcast"),
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        if preferences.isEnabled(item.id) {
            ForEach(controller.slots.flatMap { $0.addon.commands }.filter { $0.switchID == item.id }) { command in
                SettingsRow(title: command.name) {
                    ShortcutRecorder(action: .notchcastCommand(entryID: command.id))
                }
            }
            if let context = controller.context(forSwitch: item.id) {
                ForEach(controller.slots.flatMap(\.settings).filter { $0.row.switchID == item.id }) { entry in
                    entry.row.view(context)
                }
            }
        }
    }
}
