import SwiftUI

/// D15: a long song name on a pill without a notch either widens the island or scrolls inside it.
struct SpotifyIslandSettingsRow: View {
    let context: NotchcastContext
    @State private var overflow = IslandMediaOverflow.fit

    var body: some View {
        Picker(String(localized: "Long Song Names", table: "NotchcastSpotify"), selection: $overflow) {
            Text("Widen", tableName: "NotchcastSpotify").tag(IslandMediaOverflow.fit)
            Text("Scroll", tableName: "NotchcastSpotify").tag(IslandMediaOverflow.scroll)
        }
        .onAppear {
            overflow = context.defaults.string(forKey: SpotifyIsland.overflowKey)
                .flatMap(IslandMediaOverflow.init) ?? .fit
        }
        .onChange(of: overflow) { _, value in
            if let island = context.module(SpotifyModule.self)?.island {
                island.overflow = value
            } else {
                context.defaults.set(value.rawValue, forKey: SpotifyIsland.overflowKey)
            }
        }
    }
}
