import AppKit

/// screencaptureui taking key for a screenshot leaves the palette up, and the palette takes key back after it.
@MainActor
enum PaletteScreenshotHold {
    nonisolated static let captureBundleID = "com.apple.screencaptureui"

    enum Change: Sendable {
        case activated, deactivated, terminated
    }

    private static var observers: [NotificationToken] = []

    nonisolated static func holds(frontmost bundleID: String?) -> Bool {
        bundleID == captureBundleID
    }

    /// The capture app coming forward again keeps the hold; it leaving, or any other app arriving, ends it.
    nonisolated static func releases(_ change: Change, bundleID: String?) -> Bool {
        bundleID == captureBundleID ? change != .activated : change == .activated
    }

    static func holds(_ panel: NSWindow) -> Bool {
        guard holds(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return false }
        let center = NSWorkspace.shared.notificationCenter
        let changes: [(Notification.Name, Change)] = [
            (NSWorkspace.didActivateApplicationNotification, .activated),
            (NSWorkspace.didDeactivateApplicationNotification, .deactivated),
            (NSWorkspace.didTerminateApplicationNotification, .terminated),
        ]
        observers = changes.map { name, change in
            NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { [weak panel] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                Task { @MainActor [weak panel] in
                    guard releases(change, bundleID: bundleID) else { return }
                    observers = []
                    guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                    panel.makeKeyAndOrderFront(nil)
                }
            }, center: center)
        }
        return true
    }
}
