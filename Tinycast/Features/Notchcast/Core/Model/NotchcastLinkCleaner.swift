// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's URL cleaning tables and query slicing.

import Foundation

/// Drops tracking parameters from a link and leaves every other byte of it alone.
nonisolated enum NotchcastLinkCleaner {
    /// The one tracking list of the fork; besides these, every `utm_*` name counts.
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid",
        "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src",
        "li_fat_id", "__twitter_impression", "fb_action_ids", "fb_action_types", "fb_source", "mibextid",
    ]

    /// Trackers of one site only: `t` tracks on X and is the playback position on YouTube.
    static let siteNames: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature", "kw"],
        "youtu.be": ["si", "pp", "feature", "kw"],
        "twitter.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "x.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "instagram.com": ["igsh"],
        "spotify.com": ["si"],
        "reddit.com": [
            "correlation_id", "ref_campaign", "ref_source", "rdt", "share_id",
            "_branch_match_id", "$deep_link", "$3p", "$original_url",
        ],
        "tiktok.com": [
            "u_code", "preview_pb", "_d", "_t", "_r", "timestamp", "user_id",
            "share_app_name", "share_iid",
        ],
        "bilibili.com": [
            "spm_id_from", "from_spmid", "from_source", "share_source", "share_from",
            "share_medium", "share_plat", "share_tag", "share_session_id", "msource",
            "refer_from", "seid", "unique_k", "vd_source", "plat_id", "buvid", "bbid",
            "up_id", "is_story_h5", "timestamp", "ts", "visit_id", "session_id",
            "broadcast_type", "is_room_feed",
        ],
        "xiaohongshu.com": [
            "xhsshare", "author_share", "xsec_source", "share_from_user_hidden",
            "shareredid", "share_id", "exsource", "app_version", "app_platform",
            "apptime", "appuid",
        ],
    ]

    /// A parameter name as rules spell it: percent-decoded and lowercased.
    static func normalized(_ name: some StringProtocol) -> String {
        (name.removingPercentEncoding ?? String(name)).lowercased()
    }

    /// The names of every site in `sites` that is `host` or a parent domain of it.
    static func names(in sites: [String: Set<String>], forHost host: String) -> Set<String> {
        let host = host.lowercased()
        return sites.reduce(into: []) { names, site in
            if host == site.key || host.hasSuffix("." + site.key) { names.formUnion(site.value) }
        }
    }

    /// Whether a normalized name is a built-in tracker on `host`.
    static func isTracking(_ name: String, host: String = "") -> Bool {
        name.hasPrefix("utm_") || trackingNames.contains(name) || names(in: siteNames, forHost: host).contains(name)
    }

    static func clean(_ link: String) -> String {
        let host = URLComponents(string: link)?.host ?? ""
        return clean(link) { isTracking($0, host: host) }
    }

    /// Slices by scalars: `URLComponents` re-encodes, and a combining mark can hide a delimiter.
    static func clean(_ link: String, strips: (String) -> Bool) -> String {
        let scalars = link.unicodeScalars
        let fragment = scalars.firstIndex(of: "#") ?? scalars.endIndex
        guard let mark = scalars[..<fragment].firstIndex(of: "?") else { return link }
        let pairs = scalars[scalars.index(after: mark)..<fragment].split(separator: "&", omittingEmptySubsequences: false)
        let kept = pairs.filter { !strips(normalized(String($0.prefix { $0 != "=" }))) }
        guard kept.count != pairs.count else { return link }
        let query = kept.map { String($0) }.joined(separator: "&")
        return String(scalars[..<mark]) + (kept.isEmpty ? "" : "?" + query) + String(scalars[fragment...])
    }
}
