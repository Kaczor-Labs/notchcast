// notchcast-addon-order: 95
// notchcast-readme: Capture: screen recordings you trim before keeping them
import SwiftUI

/// Area, window and screen recordings with system audio, trimmed before they are kept.
enum ScreenRecordingAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "recording",
            title: String(localized: "Screen Recording", table: "NotchcastScreenRecording"),
            subtitle: String(localized: "Record an area, window or screen, then trim it.", table: "NotchcastScreenRecording"),
            category: .capture,
            requiredGrants: [.screenRecording]
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "record-area", name: String(localized: "Record Area", table: "NotchcastScreenRecording"),
            symbol: "rectangle.dashed.badge.record", switchID: ScreenRecordingModule.switchID
        ) { $0.module(ScreenRecordingModule.self)?.record(.area) },
        NotchcastCommand(
            slug: "record-window", name: String(localized: "Record Window", table: "NotchcastScreenRecording"),
            symbol: "macwindow", switchID: ScreenRecordingModule.switchID
        ) { $0.module(ScreenRecordingModule.self)?.record(.window) },
        NotchcastCommand(
            slug: "record-screen", name: String(localized: "Record Screen", table: "NotchcastScreenRecording"),
            symbol: "record.circle", switchID: ScreenRecordingModule.switchID
        ) { $0.module(ScreenRecordingModule.self)?.record(.screen) },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: ScreenRecordingModule.switchID) {
            AnyView(ScreenRecordingSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ScreenRecordingModule(context: context, system: .live)
    }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ScreenRecordingRecovery(context: context, system: .live)
    }
}
