import SwiftUI

enum DisplaySoundAddon: NotchcastAddon {
    static let brightnessID = "displayBrightness"
    static let volumeID = "volumeLevels"

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
            id: "volumeLevels",
            title: String(localized: "Volume in Island", table: "NotchcastDisplaySound"),
            subtitle: String(localized: "Replaces the macOS volume overlay.", table: "NotchcastDisplaySound"),
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
