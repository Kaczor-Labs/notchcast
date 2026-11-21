// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's music block replacement: Play/Pause alone asks a player to play.

import Foundation

/// A player that announces its state, so the play key can find it once it no longer owns Now Playing.
struct LastPlayer: Equatable, Sendable {
    /// How asking a player to play ended.
    enum Outcome: Equatable, Sendable {
        case played
        /// macOS refused the Apple event: Automation access is off for this player.
        case refused
        case failed
    }

    let bundleID: String
    let name: String
    let announcement: String
    /// Its scripting dictionary's `play` command, event class then event id; nil for one never resumed.
    let playEvent: String?

    static let storeKey = "musicBlockLastPlayer"

    static let known: [LastPlayer] = [
        LastPlayer(bundleID: "com.spotify.client", name: "Spotify",
                   announcement: "com.spotify.client.PlaybackStateChanged", playEvent: "spfyPlay"),
        LastPlayer(bundleID: "com.apple.Music", name: "Apple Music",
                   announcement: "com.apple.Music.playerInfo", playEvent: nil),
    ]

    /// The player behind an announcement whose "Player State" says it is playing now.
    static func playing(announcement: String, state: String?) -> LastPlayer? {
        guard state?.lowercased() == "playing" else { return nil }
        return known.first { $0.announcement == announcement }
    }

    /// Only the play key resumes, and only a player with a play command that is not the app being blocked.
    static func resume(_ lastBundleID: String?, after key: NotchcastMediaKey.Key?) -> LastPlayer? {
        guard key == .play, let player = known.first(where: { $0.bundleID == lastBundleID }),
              player.playEvent != nil, !MusicLaunchPolicy.blockedBundleIDs.contains(player.bundleID)
        else { return nil }
        return player
    }

    /// An Apple event status, as the notice it calls for.
    static func outcome(status: Int, refused: [Int]) -> Outcome {
        status == 0 ? .played : refused.contains(status) ? .refused : .failed
    }
}
