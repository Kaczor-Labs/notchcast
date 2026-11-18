import CryptoKit
import Foundation

/// A `.torrent` file checked the way aria2c will read it, with the info hash that names it.
nonisolated struct TorrentMetainfo: Equatable, Sendable {
    static let maxBytes = 16 * 1024 * 1024

    let infoHash: String
    let name: String
    let data: Data

    init?(data: Data) {
        guard data.count <= Self.maxBytes, let parsed = try? TorrentBencode.parse(data),
              let range = parsed.info, case .dictionary = parsed.value["info"] else { return nil }
        infoHash = Insecure.SHA1.hash(data: data.subdata(in: range)).map { String(format: "%02x", $0) }.joined()
        name = parsed.value["info"]?["name.utf-8"]?.text ?? parsed.value["info"]?["name"]?.text ?? infoHash
        self.data = data
    }
}

/// A magnet link's BitTorrent info hash as 40 lowercase hex digits, and its display name if any.
nonisolated struct TorrentMagnet: Equatable, Sendable {
    let link: String
    let infoHash: String
    let name: String?

    init?(_ link: String) {
        guard let components = URLComponents(string: link), components.scheme?.lowercased() == "magnet",
              let items = components.queryItems else { return nil }
        let prefix = "urn:btih:"
        let topics = items.lazy.filter { $0.name == "xt" }.compactMap(\.value)
        guard let topic = topics.first(where: { $0.lowercased().hasPrefix(prefix) }),
              let hash = Self.hex(String(topic.dropFirst(prefix.count))) else { return nil }
        self.link = link
        infoHash = hash
        let name = items.first { $0.name == "dn" }?.value?.replacingOccurrences(of: "+", with: " ")
        self.name = name?.isEmpty == false ? name : nil
    }

    /// Accepts the 40-digit hex form and the 32-character base32 form, which carry the same 20 bytes.
    private static func hex(_ value: String) -> String? {
        if value.count == 40, value.allSatisfy(\.isHexDigit) { return value.lowercased() }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        guard value.count == 32 else { return nil }
        var bits = 0
        var buffer = 0
        var bytes: [UInt8] = []
        for character in value.uppercased() {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            buffer = buffer << 5 | digit
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8(truncatingIfNeeded: buffer >> bits))
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
