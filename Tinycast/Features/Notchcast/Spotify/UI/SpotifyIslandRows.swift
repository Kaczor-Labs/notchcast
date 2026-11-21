import SwiftUI

/// How the island shows the song: "Long song names" for a pill without a notch (D15).
struct SpotifyIslandRows: View {
    let context: NotchcastContext
    @AppStorage private var overflow: IslandSongOverflow
    private static let anchor = NotchcastSettingsSearch.anchor(.islandPages)

    init(context: NotchcastContext) {
        self.context = context
        _overflow = AppStorage(wrappedValue: .widen, SpotifyPlayerPage.overflowKey, store: context.defaults)
    }

    var body: some View {
        Picker(selection: $overflow) {
            Text("Widen", tableName: "NotchcastSpotify").tag(IslandSongOverflow.widen)
            Text("Scroll", tableName: "NotchcastSpotify").tag(IslandSongOverflow.scroll)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Long song names", table: "NotchcastSpotify"))
            Text("On a display without a notch, widen the island to the title or scroll it.",
                 tableName: "NotchcastSpotify")
        }
        .onChange(of: overflow) {
            guard let module = context.module(SpotifyModule.self) else { return }
            module.onPlayback?(module.playback, module.playback)
        }
    }
}
