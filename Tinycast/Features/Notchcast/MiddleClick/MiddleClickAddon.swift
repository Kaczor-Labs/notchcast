// notchcast-addon-order: 40
// notchcast-readme: Keyboard & Mouse: trackpad middle click
import Foundation

/// Three-finger taps and presses on a trackpad become middle clicks.
enum MiddleClickAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "middleClick",
            title: String(localized: "Trackpad middle click", table: "NotchcastMiddleClick"),
            subtitle: String(
                localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.",
                table: "NotchcastMiddleClick"),
            category: .keyboardMouse, defaultEnabled: true, requiredGrants: [.accessibility]),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        MiddleClickModule(context: context)
    }
}
