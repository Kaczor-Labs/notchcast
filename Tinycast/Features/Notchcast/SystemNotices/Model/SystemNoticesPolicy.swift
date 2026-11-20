// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// BatteryWatch adapted from Vorssaint faada18's NotchService.powerChanged: the 20% once-per-discharge warning.

import Foundation

/// One link (Wi-Fi or VPN): announces a change only once it has held for `settle`, never the state at start.
struct LinkWatch: Equatable, Sendable {
    static let settle: TimeInterval = 5
    /// After a login or a wake the links come back on their own; that is not news.
    static let wakeQuiet: TimeInterval = 30

    private(set) var announced: Bool?
    private var current: Bool?
    private var changedAt = Date.distantPast
    private var quietUntil = Date.distantPast

    /// The first reading is a silent baseline; while quiet a link coming up is too, a drop waits for the end.
    mutating func observe(_ up: Bool, at now: Date) {
        if current != up {
            current = up
            changedAt = now
        }
        if announced == nil || (up && now < quietUntil) { announced = up }
    }

    /// Quiet until `until` (`.distantFuture` while asleep): a link that is up now is taken as said.
    mutating func quiet(until: Date) {
        quietUntil = until
        if current == true { announced = true }
    }

    /// When `due` should next run, nil while nothing is pending or the Mac sleeps.
    var deadline: Date? {
        guard let current, current != announced, quietUntil != .distantFuture else { return nil }
        return max(changedAt, quietUntil).addingTimeInterval(Self.settle)
    }

    /// The new state to announce, once it has held for `settle` past any quiet; a flap is never announced.
    mutating func due(at now: Date) -> Bool? {
        guard let current, announced != nil, let deadline, now >= deadline else { return nil }
        self.announced = current
        return current
    }
}

/// The Mac's own battery: warns once at 20% or below while on battery, re-armed only at 25% or above.
struct BatteryWatch: Equatable, Sendable {
    static let threshold = 20
    /// Well above the threshold, so a gauge stepping 20, 21, 20 warns once.
    static let recovery = 25

    private(set) var armed: Bool?

    /// The percent to announce, if this reading is the one that warns; the first reading is a silent baseline.
    mutating func observe(percent: Int, onAC: Bool) -> Int? {
        guard let armed else {
            self.armed = percent > Self.threshold
            return nil
        }
        if percent >= Self.recovery {
            self.armed = true
            return nil
        }
        guard armed, !onAC, percent <= Self.threshold else { return nil }
        self.armed = false
        return percent
    }
}

/// Which notices the user keeps, and their texts.
enum SystemNoticesPolicy {
    static let wifiKey = "systemNoticesWiFi"
    static let vpnKey = "systemNoticesVPN"
    static let batteryKey = "systemNoticesBattery"

    static func wifi(up: Bool) -> String {
        up ? String(localized: "Wi-Fi connected", table: "NotchcastSystemNotices")
            : String(localized: "Wi-Fi disconnected", table: "NotchcastSystemNotices")
    }

    static func vpn(up: Bool) -> String {
        up ? String(localized: "VPN connected", table: "NotchcastSystemNotices")
            : String(localized: "VPN disconnected", table: "NotchcastSystemNotices")
    }

    static func battery(_ percent: Int) -> String {
        String(localized: "Low battery: \(percent)%", table: "NotchcastSystemNotices")
    }
}
