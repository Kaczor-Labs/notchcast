import Foundation

/// The add-on's one way out: a cacheless private session, so nothing it fetches is kept on disk.
enum DayNetwork {
    /// A forecast or a quote is a few kilobytes; anything far larger is not one.
    static let maxBytes = 512 << 10

    /// Cacheless, never `URLSession.shared`, as `CurrencyRateStore` fetches.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func body(of url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard url.scheme == "https", let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= maxBytes
        else { return nil }
        return data
    }
}
