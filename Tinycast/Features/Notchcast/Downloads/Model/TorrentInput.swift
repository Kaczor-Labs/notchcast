import Foundation

/// One thing the user handed over: a magnet link, a local `.torrent` file or one on the web.
nonisolated enum TorrentInput: Hashable, Sendable {
    case magnet(String)
    case file(URL)
    case remote(URL)

    /// Every magnet link, `.torrent` file URL or absolute `.torrent` path, one per line, each once.
    static func parse(clipboard text: String) -> [TorrentInput] {
        var seen = Set<TorrentInput>()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            let input: TorrentInput? = value.hasPrefix("/")
                ? (isTorrent(value) ? .file(URL(filePath: value)) : nil)
                : URL(string: value).flatMap(classify)
            guard let input, seen.insert(input).inserted else { return nil }
            return input
        }
    }

    /// The input an opened URL stands for, nil when it is no torrent at all.
    static func classify(_ url: URL) -> TorrentInput? {
        switch url.scheme?.lowercased() {
        case "magnet": .magnet(url.absoluteString)
        case "file": isTorrent(url.path) ? .file(url) : nil
        case "http", "https": isTorrent(url.path) && url.host?.isEmpty == false ? .remote(url) : nil
        default: nil
        }
    }

    private static func isTorrent(_ path: String) -> Bool { path.lowercased().hasSuffix(".torrent") }
}
