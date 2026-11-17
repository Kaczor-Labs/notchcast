import SwiftUI

/// The Island tab's rows; the island shell's own settings live here, so the tab needs no add-on.
struct NotchcastIslandSettingsRows: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.islandShowsInCaptures) {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.showsInCaptures)
                Text("Off hides the island from screenshots, recordings and screen sharing.", tableName: "Notchcast")
            }
            Toggle(isOn: $settings.islandOutlineWhenOpen) {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.outlineWhenOpen)
                Text("A faint line around the open island in Dark.", tableName: "Notchcast")
            }
        } header: {
            SettingsSectionHeader(NotchcastSettingsSearch.island)
        }
    }
}
