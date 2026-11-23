// notchcast-addon-order: 270
// notchcast-readme: Mac Tweaks: change Finder settings
// notchcast-new-switch-ids: macTweaksCatalogue
import SwiftUI

enum MacTweaksAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "macTweaksCatalogue",
            title: String(localized: "System tweaks", table: "NotchcastMacTweaks"),
            subtitle: String(
                localized: "Show the tweak groups. Turning this off keeps your changes.",
                table: "NotchcastMacTweaks"),
            category: .macTweaks
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: settingsID) { _ in AnyView(MacTweaksSettingsView(page: .catalogue)) },
    ]

    static let finderPage = NotchcastSettingsSubpage(
        title: String(localized: "Mac Tweaks – Finder", table: "NotchcastMacTweaks")
    ) { _ in AnyView(MacTweaksSettingsView(page: .finder)) }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        MacTweaksModule(catalogue: MacTweakCatalog.finder, system: .live())
    }
}
