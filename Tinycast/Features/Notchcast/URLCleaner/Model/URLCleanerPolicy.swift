// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's URL cleaning rules and pasteboard rewrite check.

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

        /// `utm_*` in the kept field protects the whole prefix, which no single name can.
        func keeps(_ name: String) -> Bool {
            kept.contains(name) || (name.hasPrefix("utm_") && kept.contains("utm_*"))
        }
    }

    enum Key {
        static let extra = "notchcast.urlCleaner.extra"
        static let kept = "notchcast.urlCleaner.kept"
        static let sites = "notchcast.urlCleaner.sites"
    }

    /// The flavours a rewrite writes back, so nothing of these is lost.
    static let plainLinkTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-plain-text", "public.utf16-external-plain-text",
        "public.url", "public.url-name", "NSStringPboardType", "NSURLPboardType",
    ]

    /// Undeclared names that are no private note: secrets, our own writes, copied or promised files.
    static let untouchableTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.apple.is-sensitive",
        "com.tinycast.internal", "NSFilenamesPboardType", "com.apple.NSFilePromiseItemMetaData",
        "Apple files promise pasteboard type",
    ]

    /// One item of link flavours; a type the system does not declare is an app's private note about it.
    static func isPlainLink(itemTypes: [[String]], isDeclared: (String) -> Bool) -> Bool {
        guard itemTypes.count == 1, let types = itemTypes.first, !types.isEmpty else { return false }
        return types.allSatisfy { type in
            plainLinkTypes.contains(type) || (!untouchableTypes.contains(type) && !isDeclared(type))
        }
    }

    /// The cleaned link, or nil when the text is not one http(s) link or nothing in it goes.
    static func clean(_ text: String, rules: Rules) -> String? {
        guard !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
            let parts = URLComponents(string: text), parts.url != nil,
            let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = parts.host?.lowercased(), !host.isEmpty
        else { return nil }
        let added = rules.extra.union(NotchcastLinkCleaner.names(in: rules.sites, forHost: host))
        let cleaned = NotchcastLinkCleaner.clean(text) { name in
            !rules.keeps(name) && (added.contains(name) || NotchcastLinkCleaner.isTracking(name, host: host))
        }
        return cleaned == text ? nil : cleaned
    }
}
