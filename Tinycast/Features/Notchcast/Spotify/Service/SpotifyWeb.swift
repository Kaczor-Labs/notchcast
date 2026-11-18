// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's WebAPIClient.swift and LibraryService.swift: authorized Web API calls.

import Foundation

enum SpotifyWebError: Error, Equatable {
    case signedOut
    case signInAgain
    case forbidden
    case notFound
    case rateLimited(until: Date)
    case offline
    case failed(status: Int)
}

/// The user's library through the Spotify Web API, with the client id they registered (BYOK).
@MainActor
final class SpotifyWeb {
    static let baseURL = URL(string: "https://api.spotify.com/v1")!
    static let pageSize = 50
    static let searchSize = 10

    private let transport: SpotifyWebTransport
    private let now: @MainActor () -> Date
    private let store: @MainActor (SpotifyTokens?) -> Void
    private(set) var clientID: String
    private(set) var tokens: SpotifyTokens?
    private var blockedUntil: Date?

    init(clientID: String, tokens: SpotifyTokens?, transport: SpotifyWebTransport,
         now: @escaping @MainActor () -> Date, store: @escaping @MainActor (SpotifyTokens?) -> Void) {
        self.clientID = clientID
        self.tokens = tokens
        self.transport = transport
        self.now = now
        self.store = store
    }

    var isSignedIn: Bool { tokens != nil }

    /// Opens the browser, waits for the loopback redirect, then trades the code for tokens.
    func signIn(open: @MainActor (URL) -> Void) async throws(SpotifyAuthError) {
        var generator = SystemRandomNumberGenerator()
        let attempt = SpotifyAuthorization.begin(clientID: clientID, using: &generator)
        let transport = transport
        let redirect = Task {
            try await transport.awaitRedirect(SpotifyAuthorization.redirectPort, SpotifyAuthorization.redirectPath)
        }
        open(attempt.authorizeURL)
        let query: [String: String]
        do { query = try await redirect.value } catch let error as SpotifyAuthError { throw error } catch {
            throw .offline
        }
        let code = try attempt.code(from: query)
        save(try await tokenRequest(attempt.exchangeForm(code: code), previous: nil))
    }

    func signOut() { save(nil) }

    // MARK: - Library

    func playlists(offset: Int) async throws(SpotifyWebError) -> SpotifyPage {
        let data = try await get("me/playlists", paging(offset))
        return SpotifyWire.decode(SpotifyWire.Paging<SpotifyWire.Playlist>.self, data)?.page(SpotifyWire.item) ?? .empty
    }

    func albums(offset: Int) async throws(SpotifyWebError) -> SpotifyPage {
        let data = try await get("me/albums", paging(offset))
        return SpotifyWire.decode(SpotifyWire.Paging<SpotifyWire.SavedAlbum>.self, data)?
            .page { $0.album.map(SpotifyWire.item) } ?? .empty
    }

    func likedSongs(offset: Int) async throws(SpotifyWebError) -> SpotifyPage {
        let data = try await get("me/tracks", paging(offset))
        return SpotifyWire.decode(SpotifyWire.Paging<SpotifyWire.SavedTrack>.self, data)?
            .page { $0.track.flatMap(SpotifyWire.item) } ?? .empty
    }

    /// Songs first, then albums and playlists, at most `searchSize` of each.
    func search(_ text: String) async throws(SpotifyWebError) -> [SpotifyItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let data = try await get("search", [URLQueryItem(name: "q", value: query),
                                            URLQueryItem(name: "type", value: "track,album,playlist"),
                                            URLQueryItem(name: "limit", value: String(Self.searchSize))])
        guard let result = SpotifyWire.decode(SpotifyWire.Search.self, data) else { return [] }
        return (result.tracks?.page(SpotifyWire.item).items ?? []) + (result.albums?.page(SpotifyWire.item).items ?? [])
            + (result.playlists?.page(SpotifyWire.item).items ?? [])
    }

    func isSaved(_ uri: String) async throws(SpotifyWebError) -> Bool {
        let data = try await get("me/library/contains", [URLQueryItem(name: "uris", value: uri)])
        return SpotifyWire.decode([Bool].self, data)?.first ?? false
    }

    func setSaved(_ saved: Bool, uri: String) async throws(SpotifyWebError) {
        _ = try await perform(saved ? "PUT" : "DELETE", "me/library", [URLQueryItem(name: "uris", value: uri)])
    }

    // MARK: - Requests

    private func get(_ path: String, _ query: [URLQueryItem]) async throws(SpotifyWebError) -> Data {
        try await perform("GET", path, query)
    }

    private func paging(_ offset: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(Self.pageSize)), URLQueryItem(name: "offset", value: String(offset))]
    }

    private func perform(_ method: String, _ path: String, _ query: [URLQueryItem], retried: Bool = false)
        async throws(SpotifyWebError) -> Data {
        if let blockedUntil, blockedUntil > now() { throw .rateLimited(until: blockedUntil) }
        guard var current = tokens else { throw .signedOut }
        if current.needsRefresh(at: now()) { current = try await refresh(current) }
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw .failed(status: 0) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        let response: SpotifyWebTransport.Response
        do { response = try await transport.send(request) } catch { throw .offline }
        switch SpotifyWebOutcome(status: response.status, retried: retried, retryAfter: response.retryAfter) {
        case .ok: return response.body
        case .refresh:
            _ = try await refresh(current)
            return try await perform(method, path, query, retried: true)
        case .retry: return try await perform(method, path, query, retried: true)
        case .signInAgain:
            save(nil)
            throw .signInAgain
        case .forbidden: throw .forbidden
        case .notFound: throw .notFound
        case .rateLimited(let seconds):
            let until = now().addingTimeInterval(seconds)
            blockedUntil = max(blockedUntil ?? until, until)
            throw .rateLimited(until: until)
        case .failed(let status): throw .failed(status: status)
        }
    }

    private func refresh(_ current: SpotifyTokens) async throws(SpotifyWebError) -> SpotifyTokens {
        do {
            let next = try await tokenRequest(SpotifyAuthorization.refreshForm(current, clientID: clientID),
                                              previous: current)
            save(next)
            return next
        } catch .signInAgain {
            save(nil)
            throw .signInAgain
        } catch {
            throw .offline
        }
    }

    private func tokenRequest(_ form: [String: String], previous: SpotifyTokens?)
        async throws(SpotifyAuthError) -> SpotifyTokens {
        var request = URLRequest(url: SpotifyAuthorization.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(SpotifyAuthorization.formEncode(form).utf8)
        let response: SpotifyWebTransport.Response
        do { response = try await transport.send(request) } catch { throw .offline }
        return try SpotifyAuthorization.tokens(status: response.status, body: response.body, previous: previous,
                                               now: now())
    }

    private func save(_ next: SpotifyTokens?) {
        tokens = next
        store(next)
    }
}
