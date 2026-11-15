// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's music launch support: keys 16-20, a key-down only, never a repeat.

import Foundation

/// Only an observed media key explains an automatic launch of the system music app.
enum MusicLaunchPolicy {
    static let launchArmWindow: TimeInterval = 2
    static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]
    static let launchKeys: Set<NotchcastMediaKey.Key> = [.play, .next, .previous, .fast, .rewind]

    static func arms(_ key: NotchcastMediaKey) -> Bool {
        key.isDown && !key.isRepeat && key.key.map(launchKeys.contains) == true
    }

    /// A newer click or key press takes precedence over the media key; bad evidence never blocks.
    static func shouldBlock(now: TimeInterval, keyAt: TimeInterval?, gestureAge: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, let keyAt, keyAt.isFinite, keyAt >= 0,
              !gestureAge.isNaN, gestureAge >= 0 else { return false }
        let elapsed = now - keyAt
        return (0...launchArmWindow).contains(elapsed) && gestureAge > elapsed
    }
}
