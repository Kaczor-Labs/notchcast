import SwiftUI

/// A Notchcast tab: one section per category it holds, built only from those add-ons.
struct NotchcastSettingsView: View {
    let controller: NotchcastController
    let pane: NotchcastPane

    var body: some View {
        Form {
            if pane == .island {
                NotchcastIslandSettingsRows()
                NotchcastLookSection(looks: AppCore.shared.island.looks)
            }
            ForEach(pane.categories, id: \.self) { category in
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
        .settingsScrollTarget(.notchcast(pane))
        .onAppear { controller.hub.refreshPermission() }
    }
}

/// A switch, then its extra rows while it is on; its commands' hotkeys live in Settings › Commands.
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
        if preferences.isEnabled(item.id), let context = controller.context(forSwitch: item.id) {
            ForEach(controller.slots.flatMap(\.settings).filter { $0.row.switchID == item.id }) { entry in
                entry.row.view(context)
            }
        }
    }
}
