import Foundation
import Synchronization

struct WebpageSaver: Sendable {
    let destination: URL
    var tools: (any DownloadToolHost)?

    @MainActor
    func save(_ source: URL, saved: Date = .now, timeZone: TimeZone = .current) async throws -> URL {
        let article = if let api = XPost.apiURL(source) {
            try await XPost.fetch(source, from: api)
        } else {
            try await page(source)
        }
        try Task.checkCancellation()
        return try await write(article, saved: saved, timeZone: timeZone)
    }

    @concurrent
    func write(_ article: WebpageArticle, saved: Date, timeZone: TimeZone) async throws -> URL {
        try Task.checkCancellation()
        return try JobOutput.publish(Data(article.markdown(saved: saved, timeZone: timeZone).utf8), in: destination,
                                     stem: article.filename, suffix: ".md")
    }

    /// WebKit reads no PDF, so only what it refuses as not HTML goes to an installed firecrawl-local.
    @MainActor
    private func page(_ source: URL) async throws -> WebpageArticle {
        do {
            return try await WebpageExtractor().extract(source)
        } catch WebpageExtractor.Failure.unsupportedContent {
            return try await toolPage(source)
        }
    }

    @MainActor
    func toolPage(_ source: URL) async throws -> WebpageArticle {
        guard let tools, let tool = tools.find(.firecrawl) else { throw WebpageExtractor.Failure.unsupportedContent }
        switch try await Self.firecrawl(source, tool: tool, host: tools) {
        case .article(let article): return article
        case .refused: throw PublicWebAddress.Refusal.privateAddress
        case .tooLarge: throw WebpageExtractor.Failure.tooLarge
        case .unusable: throw WebpageExtractor.Failure.unsupportedContent
        }
    }

    /// The child keeps only its last 64 KB of output, so the JSON is gathered line by line instead.
    @concurrent
    private static func firecrawl(_ source: URL, tool: URL, host: any DownloadToolHost) async throws
        -> FirecrawlPage.Answer {
        let output = Gathered()
        _ = try await host.run(tool, arguments: FirecrawlPage.arguments(source), workingDirectory: nil) { line in
            output.state.withLock {
                guard !$0.overflow else { return }
                $0.data.append(contentsOf: line.utf8)
                $0.data.append(0x0A)
                $0.overflow = $0.data.count > FirecrawlPage.outputLimit
                if $0.overflow { $0.data = Data() }
            }
        }
        try Task.checkCancellation()
        let (data, overflow) = output.state.withLock { ($0.data, $0.overflow) }
        return overflow ? .tooLarge : FirecrawlPage.decode(data, source: source)
    }

    private final class Gathered: Sendable {
        let state = Mutex((data: Data(), overflow: false))
    }
}
