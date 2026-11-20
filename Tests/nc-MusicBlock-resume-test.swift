// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
import Foundation

/// Pins which announcement makes a player the last one and when the play key resumes it.
@main
struct MusicBlockResumeTests {
    static func main() {
        remembering()
        routing()
        print("Music block resume: a playing announcement names the player; play alone resumes it while it runs")
    }

    static func remembering() {
        let spotify = "com.spotify.client.PlaybackStateChanged"
        precondition(LastPlayer.playing(announcement: spotify, state: "Playing")?.bundleID == "com.spotify.client")
        precondition(LastPlayer.playing(announcement: "com.apple.Music.playerInfo", state: "Playing")?.bundleID
            == "com.apple.Music", "playing Music later makes Music the last player")
        precondition(LastPlayer.playing(announcement: spotify, state: "Paused") == nil, "a pause names no player")
        precondition(LastPlayer.playing(announcement: spotify, state: "Stopped") == nil)
        precondition(LastPlayer.playing(announcement: spotify, state: nil) == nil, "no state, no player")
        precondition(LastPlayer.playing(announcement: "org.example.Playing", state: "Playing") == nil,
                     "an unknown announcement names no player")
        for player in LastPlayer.known {
            precondition(player.playEvent.utf8.count == 8, "\(player.bundleID): class and id, four characters each")
        }
    }

    static func routing() {
        let spotify = "com.spotify.client"
        let running: (String) -> Bool = { _ in true }
        let quit: (String) -> Bool = { _ in false }
        precondition(LastPlayer.resume(spotify, after: .play, isRunning: running)?.playEvent == "spfyPlay",
                     "play with a running last player resumes it")
        precondition(LastPlayer.resume(spotify, after: .play, isRunning: quit) == nil,
                     "a last player that quit is not launched; the Music block alone applies")
        precondition(LastPlayer.resume(nil, after: .play, isRunning: running) == nil, "no last player, nothing plays")
        precondition(LastPlayer.resume("org.example.player", after: .play, isRunning: running) == nil,
                     "an id no announcement named is never sent to")
        precondition(LastPlayer.resume("com.apple.Music", after: .play, isRunning: running) == nil,
                     "the app being blocked is never asked to play")
        for key: NotchcastMediaKey.Key? in [.next, .previous, .fast, .rewind, nil] {
            precondition(LastPlayer.resume(spotify, after: key, isRunning: running) == nil,
                         "only the play key resumes; \(String(describing: key)) leaves the player alone")
        }
        var asked: [String] = []
        _ = LastPlayer.resume(spotify, after: .play) { asked.append($0); return true }
        precondition(asked == [spotify], "only the last player's own id is checked")
    }
}
