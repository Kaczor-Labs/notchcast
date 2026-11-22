import SwiftUI

/// Every display's slider under the Display Brightness switch.
struct BrightnessSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        if let displays = mainApp.notchcastStatus(for: DisplaySoundAddon.self) {
            if displays.isEmpty {
                Text("No display can be controlled.", tableName: "NotchcastDisplaySound")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(displays) { display in
                BrightnessDisplayRow(display: display) { value, id in
                    try? await mainApp.callNotchcast(.init(value: value, display: id), to: DisplaySoundAddon.self)
                }
            }
        }
    }
}
