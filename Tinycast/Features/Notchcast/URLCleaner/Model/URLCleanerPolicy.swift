import Foundation

/// Decides whether a copy is one plain link, and which of its parameters go.
nonisolated enum URLCleanerPolicy {
    /// The user's three settings fields, parsed; every name is lowercased.
    struct Rules: Equatable, Sendable {
        var extra: Set<String> = []
        var kept: Set<String> = []
        var sites: [String: Set<String>] = [:]

        init(extra: String = "", kept: String = "", sites: String = "") {
            self.extra = Self.names(extra)
            self.kept = Self.names(kept)
            for rule in sites.split(whereSeparator: { $0 == ";" || $0.isNewline }) {
                let sides = rule.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let host = sides[0].trimmingCharacters(in: .whitespaces).lowercased()
                guard sides.count == 2, !host.isEmpty else { continue }
                self.sites[host, default: []].formUnion(Self.names(sides[1]))
            }
        }

        private static func names(_ list: some StringProtocol) -> Set<String> {
            Set(list.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { $0.lowercased() })
        }

        /// A site rule covers its host and every subdomain of it.
        func names(forHost host: String) -> Set<String> {
            sites.reduce(into: extra) { names, site in
                if host == site.key || host.hasSuffix("." + site.key) { names.formUnion(site.value) }
            }
        }
    }

    enum Key {
        static let extra = "notchcast.urlCleaner.extra"
        static let kept = "notchcast.urlCleaner.kept"
        static let sites = "notchcast.urlCleaner.sites"
    }

    /// Text and link flavours only: a rewrite replaces the whole item, so anything richer blocks it.
    static let plainLinkTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-plain-text", "public.utf16-external-plain-text",
        "public.url", "public.url-name",
    ]

    static func isPlainLink(itemTypes: [[String]]) -> Bool {
        guard itemTypes.count == 1, let types = itemTypes.first, !types.isEmpty else { return false }
        return plainLinkTypes.isSuperset(of: types)
    }

    /// The cleaned link, or nil when the text is not one http(s) link or nothing in it goes.
    static func clean(_ text: String, rules: Rules) -> String? {
        guard !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
            let parts = URLComponents(string: text),
            let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = parts.host?.lowercased(), !host.isEmpty
        else { return nil }
        let added = rules.names(forHost: host)
        let cleaned = NotchcastLinkCleaner.clean(text) { raw in
            let name = NotchcastLinkCleaner.normalized(raw)
            guard !rules.kept.contains(name) else { return false }
            return added.contains(name) || NotchcastLinkCleaner.isTracking(raw)
        }
        return cleaned == text ? nil : cleaned
    }
}
