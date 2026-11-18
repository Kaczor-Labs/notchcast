import SwiftUI

enum URLCleanerAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "urlCleaner",
            title: String(localized: "Clean Copied Links", table: "NotchcastURLCleaner"),
            subtitle: String(
                localized: "Remove tracking parameters from links you copy while Clipboard History is on.",
                table: "NotchcastURLCleaner"),
            category: .launcher,
            defaultEnabled: false
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "urlCleaner") {
            AnyView(URLCleanerSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        URLCleanerModule(context: context, system: .live)
    }
}
