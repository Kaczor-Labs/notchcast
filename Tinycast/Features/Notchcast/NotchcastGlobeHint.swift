import SwiftUI

/// Globe mode's row in the Dictation pane: how the key works and what macOS must leave to it.
struct NotchcastGlobeHint: View {
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var isTrusted = Permissions.isAccessibilityTrusted()

    private var globeOwner: String? {
        if let own = hotKeys.binding(for: .dictation), own.conflicts(with: .globe) || own.conflicts(with: .doubleGlobe) {
            return hotKeys.displayName(of: .dictation)
        }
        return hotKeys.conflictOwner(of: .globe, excluding: .dictation)
            ?? hotKeys.conflictOwner(of: .doubleGlobe, excluding: .dictation)
    }

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
        .onAppear { isTrusted = Permissions.isAccessibilityTrusted() }
        // macOS announces no Accessibility grant; returning from System Settings keys the window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isTrusted = Permissions.isAccessibilityTrusted()
        }
        if let globeOwner {
            Text(String(localized: "The Globe key is also used by \(globeOwner). Change that shortcut.", table: "Notchcast"))
                .font(.caption)
                .foregroundStyle(Theme.Colors.warning)
        }
        if !isTrusted {
            Text(String(localized: "Dictation needs Accessibility access to see the Globe key.", table: "Notchcast"))
                .font(.caption)
                .foregroundStyle(Theme.Colors.warning)
        }
    }
}
