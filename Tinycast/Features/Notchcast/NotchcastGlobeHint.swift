import SwiftUI

/// Globe mode's row in the Dictation pane: how the key works and what macOS must leave to it.
struct NotchcastGlobeHint: View {
    private let isTrusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        LabeledContent {
            Button(String(localized: "Open Keyboard Settings…")) {
                AppLauncher.openSettingsPane(bundleID: "com.apple.Keyboard-Settings.extension")
            }
        } label: {
            Text(String(localized: "Globe key", table: "Notchcast"))
            Text(
                [
                    String(localized: "Tap to start and tap again to finish, or hold while you speak.", table: "Notchcast"),
                    String(localized: "Escape cancels.", table: "Notchcast"),
                    String(
                        localized: """
                            Set “Press 🌐 key to” to “Do Nothing” in Keyboard settings \
                            so macOS leaves the key to Dictation.
                            """, table: "Notchcast")
                ].joined(separator: " "))
        }
        if !isTrusted {
            Text(String(localized: "Dictation needs Accessibility access to see the Globe key.", table: "Notchcast"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
