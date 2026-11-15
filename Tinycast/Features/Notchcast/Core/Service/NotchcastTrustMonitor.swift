import AppKit

/// macOS announces no Accessibility grant, so trust is reread whenever the app or a window comes forward.
@MainActor
final class NotchcastTrustMonitor {
    private var tokens: [NotificationToken] = []

    init(hub: NotchcastTapHub, center: NotificationCenter = .default) {
        tokens = [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification].map { name in
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak hub] _ in
                Task { @MainActor in hub?.refreshPermission() }
            }
            return NotificationToken(observer, center: center)
        }
    }
}
