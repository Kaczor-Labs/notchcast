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
        if let page = try await rsrc(source) {
            article = page
        } else if let api = XPost.apiURL(source) {
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

    /// `nil` when rsrc is missing, does not read this link or fails, so the link takes the path it took before.
    @concurrent
    private func rsrc(_ source: URL) async throws -> WebpageArticle? {
        try Task.checkCancellation()
        guard let tools, let request = RsrcPage.request(source), let tool = tools.find(.rsrc) else { return nil }
        let answer: (Int32, Data)
        do {
            answer = try await capture(tool, arguments: request.arguments, limit: RsrcPage.outputLimit, with: tools)
        } catch {
            // A cancelled save ends here; a run that failed, ran late or wrote too much does not.
            try Task.checkCancellation()
            return nil
        }
        try Task.checkCancellation()
        return RsrcPage.decode(answer.1, status: answer.0, site: request.site, source: source)
    }

    @concurrent
    private func pdf(_ url: URL, source: URL) async throws -> WebpageArticle {
        try Task.checkCancellation()
        guard let tools, let tool = tools.find(.firecrawl) else { throw WebpageExtractor.Failure.unsupportedContent }
        let (status, data) = try await capture(
            tool, arguments: FirecrawlPage.arguments(url), limit: FirecrawlPage.outputLimit, with: tools)
        try Task.checkCancellation()
        switch FirecrawlPage.decode(data, status: status, source: source) {
        case .article(let article): return article
        case .refused: throw PublicWebAddress.Refusal.privateAddress
        case .unusable: throw WebpageExtractor.Failure.unsupportedContent
        }
    }

    @concurrent
    private func capture(
        _ tool: URL, arguments: [String], limit: Int, with tools: any DownloadToolHost
    ) async throws -> (Int32, Data) {
        try await withThrowingTaskGroup(of: (Int32, Data).self) { group in
            group.addTask {
                do {
                    return try await tools.capture(tool, arguments: arguments, limit: limit)
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
    }
}
