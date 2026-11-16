import Foundation

nonisolated enum DownloadsWebRules {
    static func isWebScheme(_ scheme: String?) -> Bool { ["http", "https"].contains(scheme?.lowercased() ?? "") }

    static func isXHost(_ host: String?) -> Bool {
        ["x.com", "twitter.com"].contains(host?.lowercased().replacing(/^(www|mobile)\./, with: "") ?? "")
    }

    static func isYouTubeHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtu.be" || host.hasSuffix(".youtu.be") || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid", "igsh",
        "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src", "ref_url", "spm"
    ]
}
