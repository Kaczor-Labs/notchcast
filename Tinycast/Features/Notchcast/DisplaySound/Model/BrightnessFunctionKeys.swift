// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness support: non-Apple keyboards' key codes.

import Foundation

/// The key codes a non-Apple keyboard sends for brightness, which never arrive as media keys.
enum BrightnessFunctionKeys {
    static let increase = 144
    static let decrease = 145
    static let functionIncrease = 113
    static let functionDecrease = 107

    /// F14/F15 mean brightness only while macOS's own shortcuts 53/54 do; an absent entry means on.
    static func functionKeysAdjustBrightness(symbolicHotKeys: [String: Any]?) -> Bool {
        guard let symbolicHotKeys else { return true }
        for identifier in ["53", "54"] {
            guard let entry = symbolicHotKeys[identifier] as? [String: Any] else { continue }
            if let enabled = entry["enabled"] as? Bool, !enabled { return false }
        }
        return true
    }

    /// F14/F15 count only unmodified, since a modified press is the system's own shortcut.
    static func key(keyCode: Int, modified: Bool, functionKeysAdjustBrightness: Bool) -> MediaLevelKey? {
        switch keyCode {
        case increase: .brightnessUp
        case decrease: .brightnessDown
        case functionIncrease where functionKeysAdjustBrightness && !modified: .brightnessUp
        case functionDecrease where functionKeysAdjustBrightness && !modified: .brightnessDown
        default: nil
        }
    }
}
