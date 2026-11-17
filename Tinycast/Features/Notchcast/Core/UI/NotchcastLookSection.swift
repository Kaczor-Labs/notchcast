import SwiftUI

/// One look per connected display; the list follows plug and unplug, and a change repaints live.
struct NotchcastLookSection: View {
    let looks: IslandLookStore

    var body: some View {
        Section {
            ForEach(looks.displays) { display in
                Picker(selection: Binding(get: { looks.look(display) }, set: { looks.set($0, uuid: display.uuid) })) {
                    Text("Black", tableName: "Notchcast").tag(IslandLook.black)
                    Text("Frosted", tableName: "Notchcast").tag(IslandLook.frosted)
                } label: {
                    Text(verbatim: display.name)
                }
                .accessibilityLabel(Text("Look on \(display.name)", tableName: "Notchcast"))
                .settingsEnabled(display.uuid != nil)
            }
        } header: {
            SettingsSectionHeader(NotchcastSettingsSearch.look)
        }
    }
}
