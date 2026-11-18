import SwiftUI

enum URLCleanerAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "urlCleaner",
            title: String(localized: "Clean Copied Links", table: "NotchcastURLCleaner"),
            subtitle: String(
                localized: "Remove tracking parameters such as utm_source and fbclid from every link you copy.",
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
