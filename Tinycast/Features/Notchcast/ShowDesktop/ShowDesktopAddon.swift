import Foundation

enum ShowDesktopAddon: NotchcastAddon {
    static let switchID = "showDesktop"

    static let switches = [
        NotchcastSwitch(
            id: switchID,
            title: String(localized: "Show Desktop with F3", table: "NotchcastShowDesktop"),
            subtitle: String(
                localized: "Press F3 to show the desktop; press again to restore windows.",
                table: "NotchcastShowDesktop"),
            category: .keyboardMouse,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ShowDesktopModule(context: context, system: .live)
    }
}
