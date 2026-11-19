// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Island/Service/IslandCaptureSharing.swift
import AppKit

// #866: with "Show in screenshots and videos" off, titled windows stay shared and the rest hide.
@main
@MainActor
enum IslandCaptureSharingTest {
    static func main() {
        let frame = NSRect(x: -10_000, y: -10_000, width: 200, height: 100)
        let titled = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let borderless = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        check(!titled.isVisible && !borderless.isVisible, "neither window is ever shown")
        check(IslandCaptureSharing.sharing(for: titled, captures: .none) == .readOnly, "off: a titled window is shared")
        check(IslandCaptureSharing.sharing(for: borderless, captures: .none) == .none, "off: a borderless one hides")
        check(IslandCaptureSharing.sharing(for: titled, captures: .readOnly) == .readOnly, "on: titled is shared")
        check(IslandCaptureSharing.sharing(for: borderless, captures: .readOnly) == .readOnly, "on: borderless too")
        print("PASS IslandCaptureSharingTest")
    }

    static func check(_ condition: Bool, _ label: String) {
        guard !condition else { return }
        print("FAIL \(label)")
        exit(1)
    }
}
