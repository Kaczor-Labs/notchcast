import Foundation

/// The web links a command takes from copied text, each once and in the order copied.
nonisolated enum DownloadsLinks {
    static func urls(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            // A bare "example.com" stays text; only a link written with its scheme is taken.
            guard let range = Range(match.range, in: text),
                  let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  text[range].lowercased().hasPrefix(scheme + "://"),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url.absoluteString
        }
    }
}
