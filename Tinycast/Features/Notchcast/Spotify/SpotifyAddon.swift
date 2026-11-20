// notchcast-new-switch-ids: spotify
// notchcast-addon-order: 165
// notchcast-readme: Display & Sound: Spotify in the Island through Soloist
import SwiftUI

/// Spotify in the island through Soloist, Spotify's own headless player; off by default.
enum SpotifyAddon: NotchcastAddon {
    static let switchID = "spotify"

    static let switches = [
        NotchcastSwitch(
            id: "spotify",
            title: String(localized: "Spotify in the Island", table: "NotchcastSpotify"),
            subtitle: String(localized: "Play Spotify through Soloist, Spotify’s own lightweight player.",
                             table: "NotchcastSpotify"),
            category: .music),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "spotify") { AnyView(SpotifySettingsView(context: $0)) },
        NotchcastSettingsRow(switchID: "spotify") { AnyView(SpotifyIslandRows(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        let module = SpotifyModule(context: context, system: .live)
        let page = SpotifyPlayerPage(module: module)
        module.onPlayback = { _, playback in page.update(playback) }
        return module
    }
}
