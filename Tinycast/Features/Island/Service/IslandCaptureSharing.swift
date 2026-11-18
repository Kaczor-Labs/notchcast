import AppKit

/// Titled windows such as Settings always show in captures, like any app's.
@MainActor
enum IslandCaptureSharing {
    static func sharing(for window: NSWindow, captures: NSWindow.SharingType) -> NSWindow.SharingType {
        window.styleMask.contains(.titled) ? .readOnly : captures
    }
}
