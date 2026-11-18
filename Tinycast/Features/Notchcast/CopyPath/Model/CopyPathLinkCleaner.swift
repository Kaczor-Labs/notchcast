import Foundation

/// Drops tracking parameters from a link and leaves every other byte of it alone.
nonisolated enum CopyPathLinkCleaner {
    /// The one tracking list of this add-on; besides these, every `utm_*` name counts.
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid",
        "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src",
    ]

    static func isTracking(_ name: some StringProtocol) -> Bool {
        let name = (name.removingPercentEncoding ?? String(name)).lowercased()
        return name.hasPrefix("utm_") || trackingNames.contains(name)
    }

    /// Splits the query by hand, since `URLComponents` re-encodes what it rebuilds.
    static func clean(_ link: String) -> String {
        let fragment = link.firstIndex(of: "#") ?? link.endIndex
        guard let mark = link[..<fragment].firstIndex(of: "?") else { return link }
        let pairs = link[link.index(after: mark)..<fragment].split(separator: "&", omittingEmptySubsequences: false)
        let kept = pairs.filter { !isTracking($0.prefix { $0 != "=" }) }
        guard kept.count != pairs.count else { return link }
        let head = kept.isEmpty ? String(link[..<mark]) : link[...mark] + kept.joined(separator: "&")
        return head + link[fragment...]
    }
}
