// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/SpotifyAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Commands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Web.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifySystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyWeb.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyPlayerPage.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPlayerSource.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum SpotifyCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(SpotifyAddon.self) }
}

// The shipped settings views and live system are left out: these stand in so the descriptor compiles.
struct SpotifySettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct SpotifyIslandRows: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

extension SpotifySystem {
    static var live: SpotifySystem { fatalError("the harness never makes a module") }
}
