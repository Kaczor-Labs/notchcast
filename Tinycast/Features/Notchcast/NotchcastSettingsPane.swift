import SwiftUI

/// The Settings detail for a Notchcast tab (hook H7); empty only before AppCore has started.
struct NotchcastSettingsPane: View {
    let pane: NotchcastPane

    var body: some View {
        if pane == .dictation {
            NotchcastDictationPane()
        } else if let controller = AppCore.shared.notchcast?.controller {
            NotchcastSettingsView(controller: controller, pane: pane)
        }
    }
}
