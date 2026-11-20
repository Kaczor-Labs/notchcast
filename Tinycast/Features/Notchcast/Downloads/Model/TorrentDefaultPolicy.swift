import Foundation

/// What a default torrent app covers: magnet links, or `.torrent` files.
enum TorrentDefaultKind: String, CaseIterable, Sendable {
    case magnet, file
}

/// When Notchcast takes the default torrent app, and to whom it gives it back.
enum TorrentDefaultPolicy {
    /// Each claimed kind's previous app, "" if none; present only from claim to hand-back.
    typealias Record = [TorrentDefaultKind: String]

    /// One kind as Launch Services sees it: its default app, and every app that could open it.
    struct Holder: Equatable, Sendable {
        var current: String?
        var candidates: [String]
    }

    enum Step: Equatable {
        case none
        /// Saved before the claims, so a refused claim is never retried.
        case claim(Record)
        /// Give each kind to its app, then forget the record even if one fails, so switch-on claims again.
        case handBack([TorrentDefaultKind: String])
    }

    static func step(
        enabled: Bool, hasAria2c: Bool, own: String, holders: [TorrentDefaultKind: Holder], record: Record?
    ) -> Step {
        if enabled {
            guard record == nil, hasAria2c else { return .none }
            var previous = Record()
            for kind in TorrentDefaultKind.allCases where holders[kind]?.current != own {
                previous[kind] = holders[kind]?.current ?? ""
            }
            return .claim(previous)
        }
        guard let record else { return .none }
        var targets = [TorrentDefaultKind: String]()
        for (kind, saved) in record where holders[kind]?.current == own {
            let others = holders[kind]?.candidates.filter { $0 != own } ?? []
            if let next = others.contains(saved) ? saved : others.first { targets[kind] = next }
        }
        return .handBack(targets)
    }
}
