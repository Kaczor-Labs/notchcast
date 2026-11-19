// notchcast-new-switch-ids: spotify
// notchcast-addon-order: 165
import SwiftUI

/// Spotify in the island through Soloist, Spotify's own headless player; off by default.
enum SpotifyAddon: NotchcastAddon { // drift: keep the generated NotchcastRegistry lists it
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
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SpotifyModule(context: context, system: .live)
    }
}
