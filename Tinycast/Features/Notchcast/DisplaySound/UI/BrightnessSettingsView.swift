import SwiftUI

/// Every display's slider under the Display Brightness switch.
struct BrightnessSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        if let displays = mainApp.status.notchcast.displays {
            if displays.isEmpty {
                Text("No display can be controlled.", tableName: "NotchcastDisplaySound")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(displays) { display in
                BrightnessDisplayRow(display: display) { value, id in
                    guard case .brightness(let level) = try? await mainApp.callNotchcast(.setBrightness(value, id))
                    else { return nil }
                    return level
                }
            }
        }
    }
}
