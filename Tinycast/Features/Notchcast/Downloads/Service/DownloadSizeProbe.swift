import Foundation

/// Asks the server how large a direct link is, for the links yt-dlp cannot size.
enum DownloadSizeProbe {
    @concurrent
    static func bytes(of source: String) async -> Int64? {
        guard let url = URL(string: source) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              response.expectedContentLength > 0
        else { return nil }
        return response.expectedContentLength
    }
}
