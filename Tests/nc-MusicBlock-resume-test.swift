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
        outcomes()
        print("Music block resume: a playing announcement names the player; play alone resumes it; refusals are told")
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
            guard let event = player.playEvent else { continue }
            precondition(event.utf8.count == 8, "\(player.bundleID): class and id, four characters each")
        }
    }

    static func routing() {
        let spotify = "com.spotify.client"
        precondition(LastPlayer.resume(spotify, after: .play)?.playEvent == "spfyPlay", "play resumes the last player")
        precondition(LastPlayer.resume(nil, after: .play) == nil, "no last player, nothing plays")
        precondition(LastPlayer.resume("org.example.player", after: .play) == nil,
                     "an id no announcement named is never sent to")
        precondition(LastPlayer.resume("com.apple.Music", after: .play) == nil,
                     "the app being blocked is never asked to play")
        for key: NotchcastMediaKey.Key? in [.next, .previous, .fast, .rewind, nil] {
            precondition(LastPlayer.resume(spotify, after: key) == nil,
                         "only the play key resumes; \(String(describing: key)) leaves the player alone")
        }
    }

    static func outcomes() {
        let refused = [-1743, -1744]
        precondition(LastPlayer.outcome(status: 0, refused: refused) == .played)
        precondition(LastPlayer.outcome(status: -1743, refused: refused) == .refused, "denied in Automation")
        precondition(LastPlayer.outcome(status: -1744, refused: refused) == .refused, "consent never given")
        precondition(LastPlayer.outcome(status: -1712, refused: refused) == .failed, "a timeout is no refusal")
        precondition(LastPlayer.outcome(status: -600, refused: refused) == .failed, "a player gone is no refusal")
    }
}
