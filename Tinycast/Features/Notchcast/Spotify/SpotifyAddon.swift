import Carbon.HIToolbox
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

    static let commands = [
        NotchcastCommand(
            slug: "spotify-expand-player",
            name: String(localized: "Expand Player", table: "NotchcastSpotify"),
            symbol: "play.square", switchID: "spotify", keywords: ["spotify", "music", "player"],
            hyperDefault: kVK_ANSI_S,
            run: { $0.module(SpotifyModule.self)?.island.expand() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "spotify") { AnyView(SpotifySettingsView(context: $0)) },
        NotchcastSettingsRow(switchID: "spotify") { AnyView(SpotifyIslandSettingsRow(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SpotifyModule(context: context, system: .live)
    }
}
