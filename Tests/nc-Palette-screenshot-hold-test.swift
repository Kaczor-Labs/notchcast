// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/PaletteScreenshotHold.swift Tinycast/Platform/NotificationToken.swift
import AppKit

@main
struct PaletteScreenshotHoldTest {
    static func main() {
        let capture = PaletteScreenshotHold.captureBundleID
        precondition(capture == "com.apple.screencaptureui")
        precondition(PaletteScreenshotHold.holds(frontmost: capture))
        for other in [nil, "com.apple.finder", "com.apple.screencapture", "screencaptureui", "com.abueammar.tinycast"] {
            precondition(!PaletteScreenshotHold.holds(frontmost: other), "\(other ?? "nil") must not hold")
        }
        precondition(!PaletteScreenshotHold.releases(.activated, bundleID: capture))
        precondition(PaletteScreenshotHold.releases(.deactivated, bundleID: capture))
        precondition(PaletteScreenshotHold.releases(.terminated, bundleID: capture))
        for other in [nil, "com.apple.Safari", "com.abueammar.tinycast"] {
            precondition(PaletteScreenshotHold.releases(.activated, bundleID: other))
            precondition(!PaletteScreenshotHold.releases(.deactivated, bundleID: other))
            precondition(!PaletteScreenshotHold.releases(.terminated, bundleID: other))
        }
        print("PASS nc-Palette-screenshot-hold")
    }
}
