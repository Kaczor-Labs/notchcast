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
        guard status == 0, let root = object(data), root["ok"] as? Bool == true,
              let items = root["items"] as? [[String: Any]], let first = items.first else { return nil }
        let body: String
        if site == .x {
            guard items.count > 1 else { return nil }
            body = items.map(post).filter { !$0.isEmpty }.joined(separator: "\n\n")
        } else {
            // LinkedIn sends plain text, where a line end is a line end; the other two send Markdown.
            let prose: (Any?) -> String? = site == .linkedIn ? { lines($0) } : { markdown($0) }
            body = discussion(first, comments: Array(items.dropFirst()), prose: prose)
        }
        guard !body.isEmpty else { return nil }
        let host = source.host(percentEncoded: false) ?? source.absoluteString
        let title = text(first["title"]) ?? WebpageArticle.headline(text(first["text"]) ?? "") ?? host
        return WebpageArticle(title: title, author: text(first["author"]) ?? host, published: text(first["published_at"]),
                              source: source, baseURL: source, html: "", markdownBody: body)
    }

    /// Output that is not one JSON object is a failed run.
    private static func object(_ data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func post(_ item: [String: Any]) -> String {
        let raw = item["raw"] as? [String: Any] ?? [:]
        var parts = [lines(item["text"]), media(raw["media"])].compactMap { $0 }
        if let quoted = raw["quoted"] as? [String: Any] {
            let body = [handle(quoted), lines(quoted["text"]), media(quoted["media"])]
                .compactMap { $0 }.joined(separator: "\n\n")
            if !body.isEmpty { parts.append(quote(body, level: 1)) }
        }
        return parts.joined(separator: "\n\n")
    }

    /// The quoted author, linked to the quoted post when both names have the shape X gives them.
    private static func handle(_ quoted: [String: Any]) -> String? {
        guard let author = text(quoted["author"]), author.wholeMatch(of: /[A-Za-z0-9_]{1,15}/) != nil else { return nil }
        guard let id = text(quoted["id"]), id.wholeMatch(of: /[0-9]{1,20}/) != nil else { return "@\(author)" }
        return "[@\(author)](https://x.com/\(author)/status/\(id))"
    }

    private static func media(_ value: Any?) -> String? {
        let entries = (value as? [[String: Any]] ?? []).compactMap { entry -> String? in
            guard let url = web(entry["url"]) else { return nil }
            return entry["type"] as? String == "photo" ? "![](\(url))" : url
        }
        return entries.isEmpty ? nil : entries.joined(separator: "\n\n")
    }

    private static func discussion(_ post: [String: Any], comments: [[String: Any]], prose: (Any?) -> String?) -> String {
        let raw = post["raw"] as? [String: Any] ?? [:]
        var parts = [web((raw["item"] as? [String: Any])?["url"]), prose(post["text"])].compactMap { $0 }
        let replies = threaded(comments).compactMap { comment, level -> String? in
            guard let body = prose(comment["text"]) else { return nil }
            let day = text(comment["published_at"]).map { " · \($0.prefix(10))" } ?? ""
            let author = text(comment["author"]).map { safe($0.replacing(/\s+/, with: " ")) } ?? "[deleted]"
            let entry = "**\(author)**\(day)\n\n\(body)"
            return level > 0 ? quote(entry, level: min(level, 6)) : entry
        }
        if !replies.isEmpty { parts += ["## Comments"] + replies }
        return parts.joined(separator: "\n\n")
    }

    /// Reddit lists comments by score, so a reply can come before its parent; each one is moved under the comment
    /// it names as its parent. LinkedIn names none, so its comments stay a flat list.
    private static func threaded(_ comments: [[String: Any]]) -> [(comment: [String: Any], level: Int)] {
        let keys = comments.map(identity)
        let known = Set(keys.compactMap(\.id))
        var children: [String: [Int]] = [:]
        var roots: [Int] = []
        for (index, key) in keys.enumerated() {
            if let parent = key.parent, parent != key.id, known.contains(parent) {
                children[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        var result: [(comment: [String: Any], level: Int)] = []
        var seen = Set<Int>()
        var stack = roots.reversed().map { (index: $0, level: 0) }
        while let next = stack.popLast() {
            guard seen.insert(next.index).inserted else { continue }
            result.append((comments[next.index], next.level))
            let replies = keys[next.index].id.flatMap { children[$0] } ?? []
            stack += replies.reversed().map { (index: $0, level: next.level + 1) }
        }
        // Comments that only name each other have no root; they are kept, flat.
        return result + comments.indices.filter { !seen.contains($0) }.map { (comments[$0], 0) }
    }

    private static func identity(_ comment: [String: Any]) -> (id: String?, parent: String?) {
        let raw = comment["raw"] as? [String: Any] ?? [:]
        if let attrs = raw["attrs"] as? [String: Any] { return (text(attrs["thingid"]), text(attrs["parentid"])) }
        let item = raw["item"] as? [String: Any] ?? [:]
        return ((item["id"] as? Int).map(String.init), (item["parent_id"] as? Int).map(String.init))
    }

    private static func quote(_ body: String, level: Int) -> String {
        let prefix = String(repeating: "> ", count: level)
        return body.components(separatedBy: "\n")
            .map { $0.isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + $0 }.joined(separator: "\n")
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func markdown(_ value: Any?) -> String? { text(value).map(safe) }

    /// Plain text keeps its line ends: two trailing spaces make Markdown break the line there.
    private static func lines(_ value: Any?) -> String? {
        guard let text = markdown(value) else { return nil }
        let rows = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return rows.indices.map { index in
            index + 1 < rows.count && !rows[index].isEmpty && !rows[index + 1].isEmpty ? rows[index] + "  " : rows[index]
        }.joined(separator: "\n")
    }

    /// Text from the web is written as it came, except what could act when the note is opened: raw HTML,
    /// and a link or link definition that leads anywhere but a web page, a mail address or a place on the site.
    private static func safe(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "&lt;")
            .replacing(/\]\((?!\s*(?:&lt;)?(?:https?:\/\/|mailto:|\/(?!\/)|#))/, with: "]\\(")
            .replacing(/(?m)^( {0,3})\[(?=[^\]\n]*\]:)/) { "\($0.1)\\[" }
    }

    /// An https address in angle brackets, which Markdown reads as one link whatever the address holds.
    private static func web(_ value: Any?) -> String? {
        guard let url = text(value).flatMap(URL.init(string:)), url.scheme?.lowercased() == "https" else { return nil }
        let address = url.absoluteString.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
        return "<\(address)>"
    }
}
