import Foundation

/// Reads what the network tools print: the Wi-Fi device, saved networks, the public address.
enum NetworkInfoPolicy {
    /// `networksetup -listallhardwareports`: the device under "Hardware Port: Wi-Fi".
    static func wifiDevice(hardwarePorts: String) -> String? {
        var isWiFi = false
        for line in hardwarePorts.components(separatedBy: .newlines) {
            if let port = value(line, "Hardware Port:") { isWiFi = port == "Wi-Fi" || port == "AirPort" }
            if isWiFi, let device = value(line, "Device:"), !device.isEmpty { return device }
        }
        return nil
    }

    /// `networksetup -listpreferredwirelessnetworks`: one indented name per line, system order.
    static func savedNetworks(preferred: String) -> [String] {
        var seen = Set<String>()
        return preferred.components(separatedBy: .newlines).dropFirst()
            .filter { $0.first == "\t" || $0.first == " " }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func filter(_ networks: [String], query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? networks : networks.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// A lookup service's reply is trusted only when it is one bare IPv4 or IPv6 address.
    static func publicAddress(from data: Data) -> String? {
        guard data.count <= 64, let text = String(bytes: data, encoding: .utf8) else { return nil }
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isIPv4 = address.split(separator: ".", omittingEmptySubsequences: false).count == 4
            && address.split(separator: ".", omittingEmptySubsequences: false)
                .allSatisfy { $0.count <= 3 && UInt8($0) != nil }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        let isIPv6 = address.contains(":") && address.count <= 39
            && address.unicodeScalars.allSatisfy { hex.contains($0) }
        return isIPv4 || isIPv6 ? address : nil
    }

    private static func value(_ line: String, _ key: String) -> String? {
        line.hasPrefix(key) ? String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces) : nil
    }
}
