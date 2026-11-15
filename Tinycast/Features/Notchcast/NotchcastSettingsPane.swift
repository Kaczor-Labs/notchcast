import SwiftUI

/// The Settings detail for the Notchcast tab (hook H7); empty only before AppCore has started.
struct NotchcastSettingsPane: View {
    var body: some View {
        if let controller = AppCore.shared.notchcast?.controller {
            NotchcastSettingsView(controller: controller)
                .settingsScrollTarget(.notchcast)
        }
    }
}
