// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's WebAPIWire.swift, LibraryModels.swift and WebAPIClient.swift.

import Foundation

/// One row of the library: a playlist, an album or a song, as the island lists it.
struct SpotifyItem: Sendable, Equatable, Identifiable, Hashable {
    enum Kind: String, Sendable, Equatable, Hashable { case track, album, playlist }
    let kind: Kind
    /// The Spotify URI, which also plays it.
    let id: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    let count: Int?
    let durationMs: Int?
}

struct SpotifyPage: Sendable, Equatable {
    var items: [SpotifyItem]
    var nextOffset: Int?

    static let empty = SpotifyPage(items: [], nextOffset: nil)
}

/// What one Web API answer means for the caller.
enum SpotifyWebOutcome: Sendable, Equatable {
    case ok
    /// Refresh the token once and repeat the request.
    case refresh
    case signInAgain
    case forbidden
    case notFound
    case rateLimited(seconds: Double)
    /// A brief server hiccup; every request we make is safe to repeat once.
    case retry
    case failed(status: Int)

    init(status: Int, retried: Bool, retryAfter: String?) {
        switch status {
        case 200...299: self = .ok
        case 401: self = retried ? .signInAgain : .refresh
        case 403: self = .forbidden
        case 404: self = .notFound
        case 429:
            let seconds = retryAfter.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { max($0, 0) }
            self = .rateLimited(seconds: seconds ?? 2)
        case 502...504: self = retried ? .failed(status: status) : .retry
        default: self = .failed(status: status)
        }
    }
}

enum SpotifyWire {
    struct Image: Decodable, Sendable { let url: String; let width: Int? }
    struct Artist: Decodable, Sendable { let name: String }
    struct Count: Decodable, Sendable { let total: Int? }
    struct Owner: Decodable, Sendable { let id: String; let displayName: String?
        enum CodingKeys: String, CodingKey { case id, displayName = "display_name" } }

    struct Album: Decodable, Sendable {
        let uri: String
        let name: String
        let images: [Image]?
        let artists: [Artist]?
        let totalTracks: Int?
        enum CodingKeys: String, CodingKey { case uri, name, images, artists, totalTracks = "total_tracks" }
    }

    struct Track: Decodable, Sendable {
        let uri: String?
        let name: String?
        let type: String?
        let artists: [Artist]?
        let album: Album?
        let durationMs: Int?
        let isLocal: Bool?
        enum CodingKeys: String, CodingKey {
            case uri, name, type, artists, album, durationMs = "duration_ms", isLocal = "is_local"
        }
    }

    struct Playlist: Decodable, Sendable {
        let uri: String
        let name: String
        let images: [Image]?
        let owner: Owner?
        /// Spotify renamed `tracks` to `items` in Feb 2026; either may come.
        let items: Count?
        let tracks: Count?
    }

    /// Entries can be `null`, e.g. a removed playlist in search results.
    struct Paging<Item: Decodable & Sendable>: Decodable, Sendable {
        let items: [Item?]
        let offset: Int?
        let next: String?

        func page(_ transform: (Item) -> SpotifyItem?) -> SpotifyPage {
            SpotifyPage(items: items.compactMap { $0.flatMap(transform) },
                        nextOffset: next == nil ? nil : (offset ?? 0) + items.count)
        }
    }

    struct SavedTrack: Decodable, Sendable { let track: Track? }
    struct SavedAlbum: Decodable, Sendable { let album: Album? }

    struct Search: Decodable, Sendable {
        let tracks: Paging<Track>?
        let albums: Paging<Album>?
        let playlists: Paging<Playlist>?
    }

    /// The smallest image at least ~80 % of `width` px; rows draw covers at 32 pt, 64 px on Retina.
    static func imageURL(_ images: [Image]?, width: Int = 64) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let sorted = images.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
        let image = sorted.first { ($0.width ?? .max) >= width * 4 / 5 } ?? sorted.last
        return image.flatMap { URL(string: $0.url) }
    }

    static func item(_ track: Track) -> SpotifyItem? {
        guard track.type == nil || track.type == "track", track.isLocal != true,
              let uri = track.uri, let name = track.name else { return nil }
        return SpotifyItem(kind: .track, id: uri, title: name,
                           subtitle: (track.artists ?? []).map(\.name).joined(separator: ", "),
                           imageURL: imageURL(track.album?.images), count: nil, durationMs: track.durationMs)
    }

    static func item(_ album: Album) -> SpotifyItem {
        SpotifyItem(kind: .album, id: album.uri, title: album.name,
                    subtitle: (album.artists ?? []).map(\.name).joined(separator: ", "),
                    imageURL: imageURL(album.images), count: album.totalTracks, durationMs: nil)
    }

    static func item(_ playlist: Playlist) -> SpotifyItem {
        SpotifyItem(kind: .playlist, id: playlist.uri, title: playlist.name,
                    subtitle: playlist.owner?.displayName ?? "", imageURL: imageURL(playlist.images),
                    count: playlist.items?.total ?? playlist.tracks?.total, durationMs: nil)
    }

    static func decode<T: Decodable>(_: T.Type, _ data: Data) -> T? { try? JSONDecoder().decode(T.self, from: data) }
}
