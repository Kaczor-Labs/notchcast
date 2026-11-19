// notchcast-addon-order: 110
// notchcast-readme: Display & Sound: brightness keys for every display, volume in the island
// notchcast-new-switch-ids: extraDimming
import SwiftUI

enum DisplaySoundAddon: NotchcastAddon {
    static let brightnessID = "displayBrightness"
    static let volumeID = "volumeLevels"
    static let extraDimmingID = "extraDimming"

    static let switches = [
        NotchcastSwitch(
            id: "displayBrightness",
            title: String(localized: "Display Brightness", table: "NotchcastDisplaySound"),
            subtitle: String(
                localized: "Brightness keys control every display, external ones too.", table: "NotchcastDisplaySound"),
            category: .displaySound,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
        NotchcastSwitch(
            id: "extraDimming",
            title: String(localized: "Extra dimming", table: "NotchcastDisplaySound"),
            subtitle: String(
                localized: "Brightness keys dim past the lowest backlight level until sleep, reconnect or quit.",
                table: "NotchcastDisplaySound"),
            category: .displaySound,
            defaultEnabled: true,
            dependencies: ["displayBrightness"]
        ),
        NotchcastSwitch(
            id: "volumeLevels",
            title: String(localized: "Volume in Island", table: "NotchcastDisplaySound"),
            subtitle: String(
                localized: "Replaces the macOS volume overlay. Volume keys also reach a monitor's own speakers.",
                table: "NotchcastDisplaySound"),
            category: .displaySound,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "displayBrightness") { AnyView(BrightnessSettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DisplaySoundModule(context: context, system: .live)
    }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DisplaySoundRecovery(system: .live)
    }

    static func recovery(_ context: NotchcastContext, system: DisplaySoundSystem) -> DisplaySoundRecovery {
        context.recovery(DisplaySoundRecovery.self) ?? DisplaySoundRecovery(system: system)
    }
}
