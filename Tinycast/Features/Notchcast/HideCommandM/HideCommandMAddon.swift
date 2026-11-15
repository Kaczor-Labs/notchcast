import Foundation

enum HideCommandMAddon: NotchcastAddon {
    static let switchID = "hideCommandM"

    static let switches = [
        NotchcastSwitch(
            id: switchID,
            title: String(localized: "Hide with ⌘M", table: "NotchcastHideCommandM"),
            subtitle: String(
                localized: "Hide the front app instead of minimizing its window.", table: "NotchcastHideCommandM"),
            category: .keyboardMouse,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        HideCommandMModule(context: context, system: .live)
    }
}
