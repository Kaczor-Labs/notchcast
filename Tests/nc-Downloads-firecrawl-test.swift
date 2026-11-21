// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/CaptionText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/FirecrawlPage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLMarkdown.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageArticle.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageExtraction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebAddress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebProxy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
import Foundation
import Synchronization

@main
@MainActor
struct DownloadsFirecrawlTest {
    static var passes = 0
    static var failures = 0
    static let base = URL(string: "https://example.com/articles/page")!
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-firecrawl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        firecrawlDecoding()
        try await firecrawlTool(root)
        try await firecrawlDeadline(root)
        print("Downloads PDF: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func article() -> WebpageArticle {
        WebpageArticle(title: "HTML title", author: "Author", published: nil,
                       source: base, baseURL: base, html: "<p>An article.</p>")
    }

    static let pdf = URL(string: "https://example.com/papers/paper.pdf")!
    static let readable = String(repeating: "Readable text from the PDF. ", count: 6)

    static func answer(markdown: String = readable, status: Int = 200, metadata: [String: Any] = [:],
                       extra: [String: Any] = [:]) -> Data {
        let defaults: [String: Any] = ["statusCode": status, "contentType": "application/pdf"]
        var page: [String: Any] = ["markdown": markdown, "source": "local",
                                   "metadata": metadata.merging(defaults) { provided, _ in provided }]
        page.merge(extra) { _, b in b }
        return (try? JSONSerialization.data(withJSONObject: ["success": true, "data": page])) ?? Data()
    }

    static func firecrawlDecoding() {
        let arguments = FirecrawlPage.arguments(pdf)
        expect(arguments.first == "scrape" && arguments.contains(pdf.absoluteString) && arguments.contains("--public-only"),
               "firecrawl-local is asked for one public-only page")
        let metadata: [String: Any] = ["title": "A paper", "author": "A Writer", "publishedTime": "2026-01-02T10:00:00Z"]
        if case .article(let article) = FirecrawlPage.decode(answer(metadata: metadata), source: pdf) {
            let text = article.markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
            expect(article.title == "A paper" && article.author == "A Writer", "firecrawl metadata names the article")
            expect(text.contains("published: 2026-01-02") && text.contains(readable) && text.contains("# A paper"),
                   "firecrawl Markdown is written as given, under today's front matter")
            expect(article.filename == "A Writer - A paper", "firecrawl article keeps the usual file name")
        } else { expect(false, "a good firecrawl answer is an article") }
        for (body, title) in [("#### Licence notice\n\n## Paper title\n\n" + readable, "Paper title"),
                              ("### Only deep\n\n" + readable, "Only deep"), (readable, "example.com"),
                              ("## **Bold** `code` title ##\n\n" + readable, "Bold code title")] {
            if case .article(let article) = FirecrawlPage.decode(answer(markdown: body), source: pdf) {
                expect(article.title == title && article.author == "example.com", "firecrawl title falls back to \(title)")
            } else { expect(false, "untitled firecrawl answer is still an article") }
        }
        let unusable: [(String, Data)] = [
            ("blocked", answer(extra: ["blocked": true])), ("warning", answer(extra: ["warning": "needs a browser"])),
            ("HTTP 404 with exit 0", answer(status: 404)), ("empty text", answer(markdown: " ")),
            ("short text", answer(markdown: "Too short.")), ("broken JSON", Data("{\"success\": tr".utf8)),
            ("failure", Data(#"{"success":false,"code":"TIMEOUT","error":"timed out"}"#.utf8)),
            ("JSON", answer(metadata: ["contentType": "application/json"])),
            ("text", answer(metadata: ["contentType": "text/plain; charset=utf-8"])),
        ]
        if case .article = FirecrawlPage.decode(answer(metadata: ["contentType": "Application/PDF; qs=1"]), source: pdf) {
            expect(true, "")
        } else { expect(false, "firecrawl content type is matched without case") }
        for (name, data) in unusable {
            if case .unusable = FirecrawlPage.decode(data, source: pdf) { expect(true, "") } else {
                expect(false, "firecrawl \(name) is not usable")
            }
        }
        let refusal = Data(#"{"success":false,"code":"BLOCKED_TARGET","error":"127.0.0.1 is a private address"}"#.utf8)
        if case .refused = FirecrawlPage.decode(refusal, source: pdf) { expect(true, "") } else {
            expect(false, "firecrawl private-target refusal is final")
        }
    }

    static func firecrawlTool(_ root: URL) async throws {
        let bin = root.appending(path: "firecrawl-bin", directoryHint: .isDirectory)
        let files = root.appending(path: "firecrawl-output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(bin.path)/args'
        printf '%s\\n' "$FIRECRAWL_CLOUD" > '\(bin.path)/cloud'
        /bin/cat '\(bin.path)/answer.json'
        [ -f '\(bin.path)/fail' ] && exit 1
        exit 0
        """
        let tool = bin.appending(path: "firecrawl-local")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let host = DownloadToolLookup(directories: [bin])
        let saver = WebpageSaver(destination: files, tools: host)
        let args = bin.appending(path: "args")
        let output = bin.appending(path: "answer.json")
        let fail = bin.appending(path: "fail")
        let long = String(repeating: "A long line of PDF text that keeps going. ", count: 5_000)
        try answer(markdown: long, metadata: ["title": "Long"]).write(to: output)

        for mime in ["application/json", "text/plain"] {
            do {
                _ = try await saver.save(base) { _ in
                    try await WebpageExtractor.classify(response(base, mime: mime)) { _ in false }
                }
                expect(false, "a \(mime) response is refused")
            } catch WebpageExtractor.Failure.unsupportedContent {
                expect(!FileManager.default.fileExists(atPath: args.path), "a \(mime) response never starts the tool")
            }
        }
        let html = try await saver.save(base) { _ in .article(article()) }
        expect(!FileManager.default.fileExists(atPath: args.path), "HTML uses its extracted article without the tool")
        try FileManager.default.removeItem(at: html)

        let saved = try await saver.save(base) { _ in
            try await WebpageExtractor.classify(response(pdf, mime: "application/pdf")) { _ in
                expect(false, "a PDF Content-Type needs no signature probe")
                return false
            }
        }
        let markdown = try String(contentsOf: saved, encoding: .utf8)
        expect(markdown.contains(long), "a single JSON line longer than 64 KB is saved whole")
        try FileManager.default.removeItem(at: saved)
        let arguments = try String(contentsOf: args, encoding: .utf8)
        expect(arguments.split(separator: "\n").map(String.init) == FirecrawlPage.arguments(pdf),
               "the tool uses the confirmed PDF URL, --public-only and --browser never")
        let cloud = try String(contentsOf: bin.appending(path: "cloud"), encoding: .utf8)
        expect(cloud == "off\n", "the tool runs with its cloud off")
        let sniffed = try await saver.save(pdf) { _ in
            try await WebpageExtractor.classify(response(pdf, mime: "application/octet-stream")) { _ in true }
        }
        try FileManager.default.removeItem(at: sniffed)

        do {
            _ = try await host.capture(tool, arguments: FirecrawlPage.arguments(pdf), limit: 65_536)
            expect(false, "a long line crosses the raw output limit")
        } catch is ChildProcess.OutputLimitExceeded { expect(true, "") }

        for host in [nil, DownloadToolLookup(directories: [])] as [(any DownloadToolHost)?] {
            do {
                _ = try await WebpageSaver(destination: files, tools: host).save(pdf) { .pdf($0) }
                expect(false, "without firecrawl-local a PDF keeps today's error")
            } catch WebpageExtractor.Failure.unsupportedContent { expect(true, "") }
        }

        for (name, data, nonzero) in [
            ("nonzero exit", answer(), true),
            ("blocked page", answer(extra: ["blocked": true]), false),
            ("non-2xx page", answer(status: 302), false),
            ("malformed JSON", Data("{\"success\": tr".utf8), false),
            ("JSON response", answer(metadata: ["contentType": "application/json"]), false),
            ("text response", answer(metadata: ["contentType": "text/plain"]), false),
        ] {
            try data.write(to: output)
            if nonzero { try Data().write(to: fail) }
            do {
                _ = try await saver.save(pdf) { .pdf($0) }
                expect(false, "a \(name) answer is refused")
            } catch WebpageExtractor.Failure.unsupportedContent {
                let contents = try FileManager.default.contentsOfDirectory(atPath: files.path)
                expect(contents.isEmpty, "a \(name) answer writes no file")
            }
            if nonzero { try FileManager.default.removeItem(at: fail) }
        }
        try Data(#"{"success":false,"code":"BLOCKED_TARGET","error":"private"}"#.utf8).write(to: output)
        try Data().write(to: fail)
        do {
            _ = try await saver.save(pdf) { .pdf($0) }
            expect(false, "a private-target refusal shows ours")
        } catch PublicWebAddress.Refusal.privateAddress { expect(true, "") }
    }

    static func response(_ url: URL, mime: String) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!
    }

    static func firecrawlDeadline(_ root: URL) async throws {
        let destination = root.appending(path: "timeout-output")
        let child = HangingTool()
        let saver = WebpageSaver(destination: destination, tools: child, waitForDeadline: {
            var events = child.started.stream.makeAsyncIterator()
            _ = await events.next()
        })
        do {
            _ = try await saver.save(pdf) { .pdf($0) }
            expect(false, "the PDF deadline fails the save")
        } catch WebpageExtractor.Failure.timedOut {
            expect(child.stopped.withLock { $0 }, "the deadline awaits child cancellation")
        }

        let cancelled = HangingTool()
        let task = Task {
            try await WebpageSaver(destination: destination, tools: cancelled).save(pdf) { .pdf($0) }
        }
        var events = cancelled.started.stream.makeAsyncIterator()
        _ = await events.next()
        task.cancel()
        do {
            _ = try await task.value
            expect(false, "cancelling a save fails the save")
        } catch is CancellationError {
            expect(cancelled.stopped.withLock { $0 }, "cancelling the save awaits child cancellation")
        }
        expect(!FileManager.default.fileExists(atPath: destination.path), "timeout and cancellation write no file")
    }
}

private final class HangingTool: DownloadToolHost {
    let started = AsyncStream<Void>.makeStream()
    let stopped = Mutex(false)

    func find(_ tool: DownloadTool) -> URL? { URL(filePath: "/fake/" + tool.name) }

    func capture(_ executable: URL, arguments: [String], limit: Int) async throws -> (status: Int32, data: Data) {
        let lifetime = AsyncStream<Void>.makeStream()
        defer { stopped.withLock { $0 = true } }
        started.continuation.yield()
        var events = lifetime.stream.makeAsyncIterator()
        _ = await events.next()
        throw CancellationError()
    }

    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult {
        throw POSIXError(.ENOSYS)
    }
}
