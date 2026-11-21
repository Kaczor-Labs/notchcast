import Foundation

struct WebpageSaver: Sendable {
    let destination: URL
    var tools: (any DownloadToolHost)?
    var waitForDeadline: @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(60)) }

    @MainActor
    func save(
        _ source: URL, saved: Date = .now, timeZone: TimeZone = .current,
        extract: (URL) async throws -> WebpageExtractor.Page = { try await WebpageExtractor().extract($0) }
    ) async throws -> URL {
        let article: WebpageArticle
        if let api = XPost.apiURL(source) {
            article = try await XPost.fetch(source, from: api)
        } else {
            switch try await extract(source) {
            case .article(let page): article = page
            case .pdf(let url): article = try await pdf(url, source: source)
            }
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

    @concurrent
    private func pdf(_ url: URL, source: URL) async throws -> WebpageArticle {
        try Task.checkCancellation()
        guard let tools, let tool = tools.find(.firecrawl) else { throw WebpageExtractor.Failure.unsupportedContent }
        let (status, data) = try await withThrowingTaskGroup(of: (Int32, Data).self) { group in
            group.addTask {
                do {
                    return try await tools.capture(
                        tool, arguments: FirecrawlPage.arguments(url), limit: FirecrawlPage.outputLimit)
                } catch is ChildProcess.OutputLimitExceeded {
                    throw WebpageExtractor.Failure.tooLarge
                }
            }
            group.addTask {
                try await waitForDeadline()
                throw WebpageExtractor.Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
        try Task.checkCancellation()
        switch FirecrawlPage.decode(data, status: status, source: source) {
        case .article(let article): return article
        case .refused: throw PublicWebAddress.Refusal.privateAddress
        case .unusable: throw WebpageExtractor.Failure.unsupportedContent
        }
    }
}
