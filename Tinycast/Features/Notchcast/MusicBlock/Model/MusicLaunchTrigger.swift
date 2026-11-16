// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's music launch blocker: one key explains one launch, live tap only.

import Foundation

/// The last arming media key, spent by the first launch judged after it.
struct MusicLaunchTrigger {
    private var keyAt: TimeInterval?
    private var judgedProcessID: pid_t?

    /// A key sent to a music app that is already open starts no launch.
    mutating func arm(at now: TimeInterval, musicRunning: Bool) { keyAt = musicRunning ? nil : now }

    mutating func reset() { keyAt = nil }

    /// True when this launch is the one the key started; will-launch and did-launch judge it once.
    mutating func judge(bundleID: String, processID: pid_t, now: TimeInterval, gestureAge: TimeInterval,
                        tapLive: Bool) -> Bool {
        guard MusicLaunchPolicy.blockedBundleIDs.contains(bundleID), processID > 0,
              processID != judgedProcessID else { return false }
        judgedProcessID = processID
        let trigger = keyAt
        keyAt = nil
        return tapLive && MusicLaunchPolicy.shouldBlock(now: now, keyAt: trigger, gestureAge: gestureAge)
    }
}
