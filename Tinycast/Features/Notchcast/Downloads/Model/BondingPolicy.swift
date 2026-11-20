import Foundation

/// One network interface as the Mac reports it; a harness passes its own.
nonisolated struct BondingInterface: Equatable, Sendable {
    var bsdName: String
    var isWiFi: Bool
    /// The hardware port name: "iPhone USB" for a phone sharing its connection over the cable.
    var port: String
    var ipv4: [String]
}

/// The Wi-Fi and iPhone interfaces one aria2c run was started on.
nonisolated struct BondedPair: Equatable, Sendable {
    var wifi: String
    var iPhone: String

    var arguments: [String] { ["--multiple-interface=\(wifi),\(iPhone)"] }
}

/// When a download rides Wi-Fi and a plugged-in iPhone together; pure, so a harness passes interfaces.
nonisolated enum BondingPolicy {
    static let markSymbol = "iphone"

    /// The pair to hand aria2c, or nil when the job runs as it always did.
    static func pair(enabled: Bool, interfaces: [BondingInterface]) -> BondedPair? {
        enabled ? pair(in: interfaces) : nil
    }

    static func pair(in interfaces: [BondingInterface]) -> BondedPair? {
        let usable = interfaces.filter(isUsable).sorted { $0.bsdName < $1.bsdName }
        guard let wifi = usable.first(where: \.isWiFi),
              let iPhone = usable.first(where: { !$0.isWiFi && isIPhoneUSB($0.port) })
        else { return nil }
        return BondedPair(wifi: wifi.bsdName, iPhone: iPhone.bsdName)
    }

    /// True while both interfaces a run was started on are still up; this alone shows the iPhone mark.
    static func isLive(_ pair: BondedPair, in interfaces: [BondingInterface]) -> Bool {
        let up = Set(interfaces.filter(isUsable).map(\.bsdName))
        return up.contains(pair.wifi) && up.contains(pair.iPhone)
    }

    /// The island line of a bonded job; the mark leads, since the island cuts a long line at its end.
    static func marked(_ text: String) -> String {
        String(localized: "iPhone · \(text)", table: "NotchcastDownloads")
    }

    /// The BSD name ends up on aria2c's command line, so only plain ASCII letters and digits pass.
    static func isUsable(_ interface: BondingInterface) -> Bool {
        let name = interface.bsdName.unicodeScalars
        return !name.isEmpty && name.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
            && interface.ipv4.contains(where: isUsableIPv4)
    }

    static func isIPhoneUSB(_ port: String) -> Bool {
        let port = port.lowercased()
        return port.contains("iphone") && port.contains("usb")
    }

    /// Not 0.0.0.0, loopback, link-local 169.254/16, multicast or anything above it.
    static func isUsableIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let bytes = parts.compactMap { part in part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? UInt8(part) : nil }
        guard parts.count == 4, bytes.count == 4 else { return false }
        return bytes != [0, 0, 0, 0] && bytes[0] != 127 && !(bytes[0] == 169 && bytes[1] == 254) && bytes[0] < 224
    }
}
