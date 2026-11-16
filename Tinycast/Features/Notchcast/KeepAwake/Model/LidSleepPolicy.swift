// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Whether asking a closed-lid Mac to sleep is safe. Derived from Vorssaint's KeepAwakeAutomationSupport.
enum LidSleepPolicy {
    static let retryLimit = 10
    static let retryInterval: Duration = .milliseconds(500)

    /// A docked Mac on power reports clamshell sleep as allowed, so it also needs battery or no display.
    static func isAllowed(
        systemAllowsSleep: Bool?, externalDisplayConnected: Bool?, connectedToPower: Bool?,
        assertions: [[String: Any]]?
    ) -> Bool {
        guard systemAllowsSleep == true, let assertions,
            connectedToPower == false || externalDisplayConnected == false
        else { return false }
        return !assertions.contains(where: blocksLidSleep)
    }

    /// Ordinary idle assertions (media included) must not defeat the cutoff; lid-specific ones do.
    private static func blocksLidSleep(_ assertion: [String: Any]) -> Bool {
        switch assertion["AssertType"] as? String {
        case "UserIsActive", "DisplayWake", "PreventSystemSleep", nil: break
        default: return false
        }
        let appliesToLid =
            assertion["AppliesOnLidClose"] as? Bool == true || assertion["ProcessingHotPlug"] as? Bool == true
        return appliesToLid && assertion["AssertLevel"] as? Int != 0
    }

    static func isScreenLocked(sessionDictionary: [String: Any]?) -> Bool {
        guard let value = sessionDictionary?["CGSSessionScreenIsLocked"] else { return false }
        if let locked = value as? Bool { return locked }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
