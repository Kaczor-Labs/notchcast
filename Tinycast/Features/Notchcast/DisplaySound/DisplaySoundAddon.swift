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

    /// v1's slugs, so a hotkey bound to one keeps working.
    static let commands = [
        preset(slug: "volume-0", percent: 0),
        preset(slug: "volume-25", percent: 25),
        preset(slug: "volume-50", percent: 50),
        preset(slug: "volume-75", percent: 75),
        preset(slug: "volume-100", percent: 100),
    ]

    private static func preset(slug: String, percent: Int) -> NotchcastCommand {
        NotchcastCommand(
            slug: slug,
            name: String(localized: "Set Volume to \(percent)%", table: "NotchcastDisplaySound"),
            symbol: "speaker.wave.2", switchID: volumeID
        ) {
            $0.module(DisplaySoundModule.self)?.setVolume(Double(percent) / 100)
        }
    }

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
