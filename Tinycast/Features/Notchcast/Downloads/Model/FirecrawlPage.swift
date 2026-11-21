import Foundation

/// One `firecrawl-local scrape` call and what its JSON answer means for a page WebKit cannot read.
nonisolated enum FirecrawlPage {
    enum Answer: Sendable {
        case article(WebpageArticle)
        case refused
        case unusable
        case tooLarge
    }

    static let outputLimit = 64 * 1024 * 1024

    static func arguments(_ source: URL) -> [String] {
        ["scrape", source.absoluteString, "--public-only", "--timeout", "60000"]
    }

    static func decode(_ data: Data, source: URL) -> Answer {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unusable }
        guard root["success"] as? Bool == true else {
            return root["code"] as? String == "BLOCKED_TARGET" ? .refused : .unusable
        }
        guard let page = root["data"] as? [String: Any], let body = page["markdown"] as? String,
              page["blocked"] as? Bool != true, (page["warning"] as? String ?? "").isEmpty else { return .unusable }
        let metadata = page["metadata"] as? [String: Any] ?? [:]
        guard let status = metadata["statusCode"] as? Int, (200..<400).contains(status),
              body.trimmingCharacters(in: .whitespacesAndNewlines).count >= 80 else { return .unusable }
        let host = source.host(percentEncoded: false) ?? source.absoluteString
        let title = text(metadata["title"]) ?? heading(in: body) ?? host
        let published = text(metadata["publishedTime"]) ?? text(metadata["article:published_time"])
        return .article(WebpageArticle(title: title, author: text(metadata["author"]) ?? host, published: published,
                                       source: source, baseURL: source, html: "", markdownBody: body))
    }

    /// A PDF's first heading is often a licence notice, so a top-level heading wins over a deeper one.
    static func heading(in body: String) -> String? {
        let headings = body.split(whereSeparator: \.isNewline).compactMap { line -> (Int, String)? in
            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
            let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : (level, title)
        }
        return (headings.first { $0.0 <= 2 } ?? headings.first)?.1
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
