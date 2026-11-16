import SwiftUI

/// Area, window and display screenshots from one frozen selection surface.
enum ScreenshotsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "screenshot",
            title: String(localized: "Screenshots", table: "NotchcastScreenshots"),
            subtitle: String(localized: "Capture an area, window or display.", table: "NotchcastScreenshots"),
            category: .capture,
            defaultEnabled: true,
            requiredGrants: [.screenRecording]
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "screenshot-area", name: String(localized: "Capture Area", table: "NotchcastScreenshots"),
            symbol: "camera.viewfinder", switchID: ScreenshotsModule.switchID
        ) { $0.module(ScreenshotsModule.self)?.captureArea() },
        NotchcastCommand(
            slug: "screenshot-display", name: String(localized: "Capture Screen", table: "NotchcastScreenshots"),
            symbol: "camera", switchID: ScreenshotsModule.switchID
        ) { $0.module(ScreenshotsModule.self)?.captureDisplay() },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: ScreenshotsModule.switchID) {
            AnyView(ScreenshotsSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ScreenshotsModule(context: context, system: .live)
    }
}
