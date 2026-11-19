// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SpotifyAuth.swift and SpotifyTokens.swift: OAuth PKCE with the user's client id.

import CryptoKit
import Foundation

struct SpotifyTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String

    /// A minute early, so no request starts with a token about to lapse.
    func needsRefresh(at now: Date) -> Bool { now.addingTimeInterval(60) >= expiresAt }
}

enum SpotifyAuthError: Error, Equatable {
    case portInUse
    case cancelled
    case denied(String)
    case stateMismatch
    case timedOut
    case rejected(status: Int)
    /// The refresh token lapsed or was revoked: sign in again.
    case signInAgain
    case offline
}

/// Authorization Code with PKCE: no client secret, the user's own app (BYOK) supplies the client id.
struct SpotifyAuthorization: Sendable, Equatable {
    /// Our own port, so Notchcast never collides with Aural's 43821 (decision D3).
    static let redirectPort: UInt16 = 43_822
    static let redirectPath = "/callback"
    static var redirectURI: String { "http://127.0.0.1:\(redirectPort)\(redirectPath)" }
    static let scopes = ["playlist-read-private", "playlist-read-collaborative", "user-library-read",
                         "user-library-modify"]
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    let clientID: String
    let verifier: String
    let state: String

    init(clientID: String, verifier: String, state: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.verifier = verifier
        self.state = state
    }

    /// A fresh attempt: 64 random verifier characters (43–128 allowed) and a 32-character state.
    static func begin<R: RandomNumberGenerator>(clientID: String, using generator: inout R) -> SpotifyAuthorization {
        SpotifyAuthorization(clientID: clientID, verifier: random(64, using: &generator),
                             state: random(32, using: &generator))
    }

    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var authorizeURL: URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        return components?.url ?? Self.authorizeURL
    }

    /// The redirect's query: the code to exchange, or why there is none.
    func code(from query: [String: String]) throws(SpotifyAuthError) -> String {
        guard query["state"] == state else { throw .stateMismatch }
        if let error = query["error"] { throw error == "access_denied" ? .cancelled : .denied(error) }
        guard let code = query["code"], !code.isEmpty else { throw .denied("no code") }
        return code
    }

    func exchangeForm(code: String) -> [String: String] {
        ["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
         "client_id": clientID, "code_verifier": verifier]
    }

    static func refreshForm(_ tokens: SpotifyTokens, clientID: String) -> [String: String] {
        ["grant_type": "refresh_token", "refresh_token": tokens.refreshToken, "client_id": clientID]
    }

    static func formEncode(_ form: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    /// The token endpoint's answer; a refresh may omit the refresh token, which then stays as it was.
    static func tokens(status: Int, body: Data, previous: SpotifyTokens?, now: Date)
        throws(SpotifyAuthError) -> SpotifyTokens {
        guard status == 200 else {
            if previous != nil, String(decoding: body.prefix(300), as: UTF8.self).contains("invalid_grant") {
                throw .signInAgain
            }
            throw .rejected(status: status)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: body),
              let refresh = token.refreshToken ?? previous?.refreshToken else { throw .rejected(status: status) }
        return SpotifyTokens(accessToken: token.accessToken, refreshToken: refresh,
                             expiresAt: now.addingTimeInterval(TimeInterval(token.expiresIn)),
                             scope: token.scope ?? previous?.scope ?? "")
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        let scope: String?
        enum CodingKeys: String, CodingKey {
            case scope, accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
        }
    }

    private static func random<R: RandomNumberGenerator>(_ length: Int, using generator: inout R) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in characters.randomElement(using: &generator) ?? "a" })
    }
}

/// What the loopback listener does with the bytes one connection sent so far.
enum SpotifyRedirectDecision: Equatable {
    case readMore
    /// Answer and keep listening: another path, a stray request or another sign-in's state.
    case reply(status: Int)
    case finish([String: String])
}

/// The first line of the loopback request, `GET /callback?code=…&state=… HTTP/1.1`, as path and query.
enum SpotifyRedirect {
    static let maxRequestBytes = 16_384

    /// Only a whole request head counts, and only one carrying this attempt's state ends the wait.
    static func decide(_ request: Data, ended: Bool, path: String, state: String) -> SpotifyRedirectDecision {
        guard request.count <= maxRequestBytes else { return .reply(status: 431) }
        guard request.range(of: Data("\r\n\r\n".utf8)) != nil else { return ended ? .reply(status: 400) : .readMore }
        guard let parsed = parse(String(decoding: request, as: UTF8.self)), parsed.path == path else {
            return .reply(status: 404)
        }
        return parsed.query["state"] == state ? .finish(parsed.query) : .reply(status: 400)
    }

    static func parse(_ request: String) -> (path: String, query: [String: String])? {
        guard let target = request.split(separator: " ", maxSplits: 2).dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1" + target) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return (components.path, query)
    }
}
