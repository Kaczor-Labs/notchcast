import SwiftUI

/// Every display's slider under the Display Brightness switch.
struct BrightnessSettingsView: View {
    let context: NotchcastContext
    @State private var controller: BrightnessController?

    var body: some View {
        Group {
            if let controller {
                if controller.currentDisplays.isEmpty {
                    Text("No display can be controlled.", tableName: "NotchcastDisplaySound")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(controller.currentDisplays) { display in
                    BrightnessDisplayRow(display: display, controller: controller)
                }
            }
        }
        .task { await attach() }
    }

    /// The core attaches the module a moment after the switch turns on, so wait for it briefly.
    private func attach() async {
        for _ in 0..<40 {
            if let module = context.module(DisplaySoundModule.self) {
                controller = module.brightness
                return
            }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
    }
}
