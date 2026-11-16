import Darwin
import Foundation

/// Which link Shorten Link takes, what it sends to TinyURL and which reply it trusts.
nonisolated enum ShortenLinkPolicy {
    enum Source: Equatable, Sendable { case clipboard, browser }

    struct Pick: Equatable, Sendable {
        let link: String
        let source: Source
    }

    static let endpoint = "https://tinyurl.com/api-create.php?url="
    static let timeout: TimeInterval = 10

    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid", "igsh",
        "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src", "ref_url", "spm",
    ]

    static func pick(clipboard: String?, browserAddress: String?) -> Pick? {
        if let link = clipboard.flatMap(firstLink) { return Pick(link: link, source: .clipboard) }
        if let link = browserAddress.flatMap(firstLink) { return Pick(link: link, source: .browser) }
        return nil
    }

    /// The first public web link in free text, already cleaned.
    static func firstLink(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let url = match.url, let link = cleanLink(url.absoluteString), isPublic(link) { return link }
        }
        return nil
    }

    /// Strips `utm_*` and known click ids; nil for anything but an http(s) link with a host.
    static func cleanLink(_ address: String) -> String? {
        guard var parts = URLComponents(string: address),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
            let host = parts.host, !host.isEmpty else { return nil }
        guard let items = parts.percentEncodedQueryItems else { return address }
        let kept = items.filter { !isTrackingParameter($0.name.removingPercentEncoding ?? $0.name) }
        guard kept.count != items.count else { return address }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return parts.string
    }

    static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    /// Cleans again here because this is the last stop before the link leaves the Mac.
    static func request(for address: String) -> URLRequest? {
        guard let link = cleanLink(address), !link.contains(where: \.isWhitespace), isPublic(link) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = link.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: endpoint + encoded) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return request
    }

    /// Only a bare `https://tinyurl.com/<path>` is copied; anything else is treated as a failure.
    static func shortLink(reply body: Data, status: Int) -> String? {
        guard status == 200,
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.contains(where: \.isWhitespace),
            let parts = URLComponents(string: text), parts.scheme == "https",
            parts.host?.lowercased() == "tinyurl.com", parts.user == nil, parts.password == nil,
            parts.port == nil, !parts.path.isEmpty, parts.path != "/" else { return nil }
        return text
    }

    static func isPublic(_ link: String) -> Bool {
        guard let host = URL(string: link)?.host(), !host.isEmpty else { return false }
        return !isPrivate(host)
    }

    static let privateSuffixes = [".localhost", ".local", ".internal", ".lan", ".home.arpa"]

    static func isPrivate(_ raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host == "localhost" || privateSuffixes.contains(where: host.hasSuffix) { return true }
        var ipv4 = in_addr()
        if inet_aton(host, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let first = value >> 24
            let second = (value >> 16) & 255
            return first == 0 || first == 10 || first == 127
                || (first == 169 && second == 254) || (first == 172 && (16...31).contains(second))
                || (first == 192 && second == 168) || (first == 100 && (64...127).contains(second))
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isPrivate(bytes.suffix(4).map(String.init).joined(separator: "."))
            }
            return bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] <= 1
                || bytes[0] & 254 == 252 || (bytes[0] == 254 && bytes[1] & 192 == 128)
        }
        // A dotless name only resolves through the local network's search domains.
        return !host.contains(".")
    }
}
