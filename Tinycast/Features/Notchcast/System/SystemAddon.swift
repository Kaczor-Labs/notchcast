import Foundation

/// The System page in the island (#977): load at a glance and a warning when the Mac runs hot.
enum SystemAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "systemPage",
            title: String(localized: "System in the Island", table: "NotchcastSystem"),
            subtitle: String(localized: "CPU, memory, disk and network at a glance, and a warning when the Mac runs hot.",
                             table: "NotchcastSystem"),
            category: .macTweaks),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SystemModule(context: context)
    }
}
