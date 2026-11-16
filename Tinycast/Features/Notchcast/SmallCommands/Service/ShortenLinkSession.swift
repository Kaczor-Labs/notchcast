import Foundation

/// Shorten Link's own session: `.ephemeral`, no URL cache, never `URLSession.shared`.
nonisolated enum ShortenLinkSession {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = ShortenLinkPolicy.timeout
        configuration.timeoutIntervalForResource = ShortenLinkPolicy.timeout
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
