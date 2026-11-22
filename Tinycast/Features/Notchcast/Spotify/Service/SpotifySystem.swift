import Foundation

enum SoloistLaunchError: Error, Equatable {
    case notInstalled
    case launchFailed
    case noSocket
}

enum SoloistInstallError: Error, Codable, Equatable {
    case download
    case unpack
    case signature
    case version
    /// Spotify has not published a build newer than the expired one yet.
    case stillExpired
    case install
}

/// One open WebSocket to Soloist.
struct SoloistLink: Sendable {
    let send: @MainActor @Sendable (SoloistCommand) async throws -> Void
    let close: @MainActor @Sendable () -> Void
}

/// What the module reads from and does to the Mac; `SpotifySystem+Live.swift` binds the real one.
@MainActor
struct SpotifySystem {
    var now: @MainActor () -> Date
    var soloistKey: @MainActor () -> String?
    var setSoloistKey: @MainActor (String?) -> Void
    var tokens: @MainActor () -> SpotifyTokens?
    var setTokens: @MainActor (SpotifyTokens?) -> Void
    var installedBuild: @MainActor () async -> SoloistBuild?
    var install: @MainActor () async throws -> SoloistBuild
    /// Hands over the stop the moment Soloist is spawned or adopted; returns its socket once listening.
    var launch: @MainActor (_ key: String, _ spawned: @escaping @MainActor (_ stop: @escaping @MainActor () -> Void) -> Void,
                            _ exited: @escaping @MainActor (SoloistExit) -> Void,
                            _ rejected: @escaping @MainActor () -> Void) async throws -> URL
    var connect: @MainActor (_ url: URL, _ event: @escaping @MainActor (SoloistEvent) -> Void,
                             _ closed: @escaping @MainActor () -> Void) -> SoloistLink
    /// Calls `fire` once `date` passes; the returned closure cancels it.
    var wake: @MainActor (_ date: Date, _ fire: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    var nowPlaying: SpotifyNowPlayingSink
    var web: SpotifyWebTransport
    var openURL: @MainActor (URL) -> Void
}

/// macOS Now Playing, so media keys and Control Center reach Soloist (decision D9).
@MainActor
struct SpotifyNowPlayingSink {
    var update: @MainActor (_ playback: SpotifyPlayback?, _ elapsed: TimeInterval) -> Void
    var commands: @MainActor (_ handler: (@MainActor (SpotifyRemoteCommand) -> Void)?) -> Void
}

enum SpotifyRemoteCommand: Sendable, Equatable {
    case toggle, play, pause, next, previous
    case seek(TimeInterval)
}

/// HTTPS for the Web API and the token endpoint; a fake answers in the harnesses.
struct SpotifyWebTransport: Sendable {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let retryAfter: String?
    }

    var send: @Sendable (URLRequest) async throws -> Response
    /// Binds the loopback redirect listener; returns only once the port is listening.
    var listen: @Sendable (_ port: UInt16, _ path: String, _ state: String) async throws -> SpotifyRedirectListener
}

/// A bound redirect listener: wait for the query carrying the attempt's state, or stop listening.
struct SpotifyRedirectListener: Sendable {
    var redirect: @Sendable () async throws -> [String: String]
    var cancel: @Sendable () -> Void
}
