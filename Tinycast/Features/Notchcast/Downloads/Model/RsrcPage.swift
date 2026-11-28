import Foundation

/// One `rsrc` call for a link the page reader handles poorly, and what its JSON answer means.
nonisolated enum RsrcPage {
    enum Site: Sendable {
        case x, reddit, hackerNews, linkedIn
    }

    struct Request: Sendable {
        let site: Site
        let arguments: [String]
    }

    static let outputLimit = 64 * 1024 * 1024
    static let comments = "50"

    static func request(_ source: URL) -> Request? {
        guard DownloadsWebRules.isWebScheme(source.scheme), let host = source.host(percentEncoded: false)?.lowercased()
        else { return nil }
        let link = source.absoluteString
        let path = source.path(percentEncoded: false)
        if DownloadsWebRules.isXHost(host), path.contains("/status/") {
            return Request(site: .x, arguments: ["x", "thread", link])
        }
        // The archive backend never drives the user's own browser or Reddit account.
        if host == "reddit.com" || host.hasSuffix(".reddit.com"), path.contains("/comments/") {
            return Request(site: .reddit, arguments: [
                "reddit", "read", link, "--comments", comments, "--backend", "arctic-shift"])
        }
        if host == "news.ycombinator.com", path == "/item" {
            return Request(site: .hackerNews, arguments: ["hn", "read", link, "--comments", comments])
        }
        if host == "linkedin.com" || host.hasSuffix(".linkedin.com"),
           path.hasPrefix("/posts/") || path.hasPrefix("/feed/update/") {
            return Request(site: .linkedIn, arguments: ["linkedin", "read", link])
        }
        return nil
    }

    /// `nil` sends the link down the path it took before: a failed run, or one X post, which `XPost` reads whole.
    static func decode(_ data: Data, status: Int32 = 0, site: Site, source: URL) -> WebpageArticle? {
        guard status == 0, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["ok"] as? Bool == true, let items = root["items"] as? [[String: Any]], let first = items.first
        else { return nil }
        let body: String
        if site == .x {
            guard items.count > 1 else { return nil }
            body = items.map(post).filter { !$0.isEmpty }.joined(separator: "\n\n")
        } else {
            body = discussion(first, comments: Array(items.dropFirst()))
        }
        guard !body.isEmpty else { return nil }
        let host = source.host(percentEncoded: false) ?? source.absoluteString
        let title = text(first["title"]) ?? WebpageArticle.headline(text(first["text"]) ?? "") ?? host
        return WebpageArticle(title: title, author: text(first["author"]) ?? host, published: text(first["published_at"]),
                              source: source, baseURL: source, html: "", markdownBody: body)
    }

    private static func post(_ item: [String: Any]) -> String {
        let raw = item["raw"] as? [String: Any] ?? [:]
        var parts = [text(item["text"]), media(raw["media"])].compactMap { $0 }
        if let quoted = raw["quoted"] as? [String: Any] {
            let lines = [text(quoted["author"]).map { "@\($0)" }, text(quoted["text"]), media(quoted["media"])]
                .compactMap { $0 }.joined(separator: "\n\n")
            if !lines.isEmpty { parts.append(quote(lines, level: 1)) }
        }
        return parts.joined(separator: "\n\n")
    }

    private static func media(_ value: Any?) -> String? {
        let lines = (value as? [[String: Any]] ?? []).compactMap { entry -> String? in
            guard let url = text(entry["url"]), URL(string: url)?.scheme == "https" else { return nil }
            return entry["type"] as? String == "photo" ? "![](\(url))" : "<\(url)>"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private static func discussion(_ post: [String: Any], comments: [[String: Any]]) -> String {
        let raw = post["raw"] as? [String: Any] ?? [:]
        let link = text((raw["item"] as? [String: Any])?["url"]).flatMap { URL(string: $0)?.scheme == "https" ? "<\($0)>" : nil }
        var parts = [link, text(post["text"])].compactMap { $0 }
        let depths = comments.map(depth)
        let top = depths.min() ?? 0
        let replies = zip(comments, depths).compactMap { comment, depth -> String? in
            guard let body = text(comment["text"]) else { return nil }
            let day = text(comment["published_at"]).map { " · \($0.prefix(10))" } ?? ""
            let entry = "**\(text(comment["author"]) ?? "[deleted]")**\(day)\n\n\(body)"
            return depth > top ? quote(entry, level: min(depth - top, 6)) : entry
        }
        if !replies.isEmpty { parts += ["## Comments"] + replies }
        return parts.joined(separator: "\n\n")
    }

    /// Hacker News counts depth from 1 as a number, Reddit from 0 as text, LinkedIn not at all.
    private static func depth(_ comment: [String: Any]) -> Int {
        let raw = comment["raw"] as? [String: Any] ?? [:]
        if let depth = raw["depth"] as? Int { return depth }
        return ((raw["attrs"] as? [String: Any])?["depth"] as? String).flatMap(Int.init) ?? 0
    }

    private static func quote(_ body: String, level: Int) -> String {
        let prefix = String(repeating: "> ", count: level)
        return body.components(separatedBy: "\n").map { (prefix + $0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
