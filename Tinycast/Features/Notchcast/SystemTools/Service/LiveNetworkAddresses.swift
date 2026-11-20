// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's network address service: interface list and connection names.

import Darwin
import SystemConfiguration

/// The Mac's local IPv4 addresses from its interface list; nothing leaves the machine.
enum LiveNetworkAddresses {
    static func read() -> [LocalAddress] {
        let names = connectionNames()
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses: [LocalAddress] = []
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard NetworkAddressPolicy.includes(
                name: name, isUp: flags & IFF_UP != 0, isRunning: flags & IFF_RUNNING != 0,
                isIPv4: Int32(address.pointee.sa_family) == AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            guard let ip = String(bytes: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
            else { continue }
            addresses.append(LocalAddress(ip: ip, connection: names[name]))
        }
        return NetworkAddressPolicy.arrange(addresses)
    }

    /// The system's own name per BSD interface ("Wi-Fi", "Ethernet").
    private static func connectionNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            names[bsd] = display
        }
        return names
    }
}
