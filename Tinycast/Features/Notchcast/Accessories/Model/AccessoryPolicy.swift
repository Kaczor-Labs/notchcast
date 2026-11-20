// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchAccessorySupport: battery episodes and the connection baseline.

import Foundation

/// Warns once per discharge at 20% or below, re-armed only by a reading of 25% or above.
struct AccessoryLowWatch: Equatable, Sendable {
    static let threshold = 20
    static let recovery = 25

    /// Per accessory: whether its current episode already warned. A missing reading ends nothing.
    private var low: [String: Bool] = [:]

    /// The accessories this reading warns for; an accessory's first reading is a silent baseline.
    mutating func consume(_ devices: [AccessoryBattery]) -> [AccessoryBattery] {
        devices.filter { device in
            guard let warned = low[device.key] else {
                low[device.key] = device.percent <= Self.threshold
                return false
            }
            if device.percent >= Self.recovery { low[device.key] = false }
            guard device.percent <= Self.threshold, !warned else { return false }
            low[device.key] = true
            return true
        }
    }

    /// A disconnect ends the accessory's record, so its next connection starts with a silent baseline again.
    mutating func forget(_ name: String) { low[AccessoryReadings.key(name)] = nil }
}

/// Bluetooth addresses connected now; only a new one is a connection worth a notice.
struct AccessoryConnections: Equatable, Sendable {
    private var connected: Set<String> = []

    mutating func baseline(_ addresses: Set<String>) { connected = addresses }

    mutating func connect(_ address: String) -> Bool { !address.isEmpty && connected.insert(address).inserted }

    mutating func disconnect(_ address: String) { connected.remove(address) }
}

enum AccessoryPolicy {
    static let connectKey = "accessoryNoticesConnect"
    static let lowKey = "accessoryNoticesLow"
    static let hideBannerKey = "accessoryNoticesHideBanner"
    /// How long after our own notice a system banner naming the same accessory counts as its duplicate.
    static let bannerWindow: TimeInterval = 10
    /// Off drops our Connected notice for Apple's own accessories, where macOS shows its banner anyway.
    static let announcesAppleConnects = true

    /// Computers, phones and network access points come and go without anyone reaching for them.
    static func announcesConnection(name: String, majorClass: UInt32) -> Bool {
        guard !(0x01...0x03).contains(majorClass) else { return false }
        return announcesAppleConnects || !isApple(name)
    }

    static func isApple(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["airpods", "beats", "magic keyboard", "magic mouse", "magic trackpad"].contains(where: name.contains)
    }

    /// A banner is ours to hide when it names an accessory we just announced, or one still low; keys are lowercased.
    static func hides(banner texts: [String], names: [String: Date], now: Date) -> Bool {
        let live = names.filter { $0.value > now }.keys.filter { !$0.isEmpty }
        let joined = texts.joined(separator: "\n").lowercased()
        return live.contains { joined.contains($0) }
    }

    static func connected(_ name: String) -> String {
        String(localized: "\(name): Connected", table: "NotchcastAccessories")
    }

    static func low(_ name: String, percent: Int) -> String {
        String(localized: "\(name): Low battery: \(percent)%", table: "NotchcastAccessories")
    }
}
