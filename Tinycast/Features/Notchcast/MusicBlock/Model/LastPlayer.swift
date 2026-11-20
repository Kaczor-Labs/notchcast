// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's music block replacement: Play/Pause alone asks a player to play.

import Foundation

/// A player that announces its state, so the play key can find it once it no longer owns Now Playing.
struct LastPlayer: Equatable, Sendable {
    let bundleID: String
    let announcement: String
    /// Its scripting dictionary's `play` command: event class then event id, four characters each.
    let playEvent: String

    static let storeKey = "musicBlockLastPlayer"

    static let known: [LastPlayer] = [
        LastPlayer(bundleID: "com.spotify.client", announcement: "com.spotify.client.PlaybackStateChanged",
                   playEvent: "spfyPlay"),
        LastPlayer(bundleID: "com.apple.Music", announcement: "com.apple.Music.playerInfo", playEvent: "hookPlay"),
    ]

    /// The player behind an announcement whose "Player State" says it is playing now.
    static func playing(announcement: String, state: Any?) -> LastPlayer? {
        guard (state as? String)?.lowercased() == "playing" else { return nil }
        return known.first { $0.announcement == announcement }
    }

    /// Only the play key resumes, and only a running player that is not the app being blocked.
    static func resume(_ lastBundleID: String?, after key: NotchcastMediaKey.Key?,
                       isRunning: (String) -> Bool) -> LastPlayer? {
        guard key == .play, let player = known.first(where: { $0.bundleID == lastBundleID }),
              !MusicLaunchPolicy.blockedBundleIDs.contains(player.bundleID), isRunning(player.bundleID)
        else { return nil }
        return player
    }
}
