// notchcast-addon-order: 50
// notchcast-readme: Display & Sound: stop Apple Music opening on media keys
import Foundation

/// Quits Apple Music when a media key, not the user, opened it.
enum MusicBlockAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "musicBlockAppleMusic",
            title: String(localized: "Stop Apple Music opening on media keys", table: "NotchcastMusicBlock"),
            subtitle: "",
            category: .music, defaultEnabled: true, requiredGrants: [.accessibility]),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        MusicBlockModule(context: context)
    }
}
