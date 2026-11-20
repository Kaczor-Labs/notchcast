// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's network address service: which interfaces carry a local address.

import Foundation

/// One local address and the system's name for the connection it is on ("Wi-Fi").
struct LocalAddress: Sendable, Equatable {
    let ip: String
    let connection: String?

    var label: String { connection.map { "\(ip) (\($0))" } ?? ip }
}

/// Which interfaces count as the Mac's own connection; loopback, tunnels and peer links never do.
enum NetworkAddressPolicy {
    static let excludedPrefixes = [
        "lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge", "ap", "anpi", "p2p", "XHC", "vmenet", "tap", "tun",
        "feth",
    ]

    /// IPv4 on an interface that is up and running.
    static func includes(name: String, isUp: Bool, isRunning: Bool, isIPv4: Bool) -> Bool {
        isIPv4 && isUp && isRunning && !name.isEmpty && !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// Duplicates dropped, sorted by address.
    static func arrange(_ addresses: [LocalAddress]) -> [LocalAddress] {
        var seen = Set<String>()
        return addresses.filter { seen.insert($0.ip).inserted }.sorted { $0.ip < $1.ip }
    }
}
