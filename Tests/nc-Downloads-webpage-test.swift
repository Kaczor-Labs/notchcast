// notchcast-hosted-only
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
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
import AppKit
import Foundation
import Network
import WebKit

/// Pins the webpage saver offline: Markdown conversion, each fixed gap, address refusals and file output.
@main
@MainActor
struct DownloadsWebpageTest {
    static var passes = 0
    static var failures = 0
    static let base = URL(string: "https://example.com/articles/page")!
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func markdown(_ html: String) -> String { HTMLMarkdown.convert(html, baseURL: base) }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-webpage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        converter()
        gaps()
        addresses()
        await cancelledResolution()
        do {
            _ = try await PublicWebAddress.resolve("example.com", port: 443) { _, _ in ["127.0.0.1"] }
            expect(false, "custom DNS lookup cannot bypass private-address refusal")
        } catch PublicWebAddress.Refusal.privateAddress {
            expect(true, "custom DNS lookup cannot bypass private-address refusal")
        }
        frontMatter()
        failureDescriptions()
        contentRules()
        try await runnerRefusals()
        try await files(root)
        firecrawlDecoding()
        try await firecrawlTool(root)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try await extraction()
        let started = ContinuousClock.now
        do {
            _ = try await WebpageExtractor { _, _ in ["127.0.0.1"] }.extract(URL(string: "http://example.com/")!)
            expect(false, "private DNS destination is refused")
        } catch let refusal as PublicWebAddress.Refusal {
            expect(refusal.localizedDescription == PublicWebAddress.Refusal.privateAddress.localizedDescription,
                   "proxy preserves private-address refusal")
            expect(started.duration(to: .now) < .seconds(15), "private-address refusal fails the page promptly")
        }
        print("Downloads webpage: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// One pin per webpage-saving gap fixed while porting from v1.
    static func gaps() {
        expect(markdown(#"<p>Read<a href="/docs"> the docs </a>now.</p>"#)
               == "Read [the docs](<https://example.com/docs>) now.", "G1 spaces at a link's edge stay outside it")
        expect(markdown(#"<p>Hello<strong> big </strong>world</p>"#) == "Hello **big** world",
               "G1 spaces at an emphasis edge stay outside it")
        expect(markdown("<pre>\n<code class=\"language-swift\">let a = 1</code></pre>") == "```swift\nlet a = 1\n```",
               "G2 code language survives whitespace before the code element")
        expect(markdown(#"<pre class="language-python"><code>print(1)</code></pre>"#) == "```python\nprint(1)\n```",
               "G2 code language is read from the pre element")
        expect(markdown("<p>1. Not a list.</p><p>- also not</p><p>+ plus</p>")
               == "1\\. Not a list.\n\n\\- also not\n\n\\+ plus", "G3 a paragraph never turns into a list")
        expect(markdown("<h2>Title<br>Subtitle</h2>") == "## Title Subtitle", "G4 a break inside a heading stays one line")
        expect(markdown("<blockquote><p>One</p><p>Two</p></blockquote>") == "> One\n>\n> Two",
               "G5 quoted paragraphs stay inside one quote")
        expect(markdown("<table><caption>Prices</caption><tr><th>A</th></tr><tr><td>1</td></tr></table>")
               == "Prices\n\n| A |\n| --- |\n| 1 |", "G6 a table caption is kept above the table")
        expect(markdown(#"<img src="data:image/gif;base64,AA" data-srcset="/lazy.jpg 1x" alt="lazy">"#)
               == "![lazy](<https://example.com/lazy.jpg>)", "G7 a lazy image is read from data-srcset")
        expect(markdown(#"<img srcset="/a-320.jpg 320w, /a-1280.jpg 1280w" alt="pic">"#)
               == "![pic](<https://example.com/a-1280.jpg>)", "G8 the largest srcset candidate is kept")
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 0, minute: 30))!
        expect(article().markdown(saved: lateNight, timeZone: warsaw).contains("\nsaved: 2026-03-05\n"),
               "G9 the saved date is the user's own day")
    }

    static func failureDescriptions() {
        let all: [WebpageExtractor.Failure] = [
            .inUse, .unavailable(404), .unsupportedContent, .blocked, .noContent, .tooLarge, .timedOut,
            .renderFailed
        ]
        let descriptions = all.map(\.localizedDescription)
        expect(descriptions.allSatisfy { !$0.isEmpty } && Set(descriptions).count == all.count,
               "queue details are non-empty and distinct")
        expect(WebpageExtractor.Failure.unavailable(404).localizedDescription.contains("404"),
               "queue detail names the HTTP status")
    }

    static func contentRules() {
        func blocked(_ url: String) -> Bool {
            WebpageWebViewConfiguration.blockedURLPatterns.contains {
                url.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
        for host in ["3dfx.de", "3abc.cafe", "0xff.example.com", "example.com"] {
            expect(!blocked("https://\(host)/"), "content rules allow hostname \(host)")
        }
        for host in ["127.0.0.1", "0x7f000001", "2130706433", "0177.1", "[::1]", "localhost"] {
            expect(blocked("https://\(host)/"), "content rules block literal or local host \(host)")
        }
    }

    static func runnerRefusals() async throws {
        let runner: any DownloadRunner = WebpageRunner()
        expect(runner.kind == "webpage" && runner.tools.isEmpty, "webpage runner needs no outside tools")
        let context = DownloadRunContext(destination: URL(filePath: "/unused-webpage-test-destination"),
                                         tools: DownloadToolLookup(directories: []))
        for source in ["file:///etc/passwd", "http://127.0.0.1/", "http://[::1]/"] {
            let job = DownloadJob(id: UUID().uuidString, kind: "webpage", source: source,
                                  title: "Refused", created: .now)
            do {
                _ = try await runner.run(job, context: context)
                expect(false, "runner refuses \(source)")
            } catch let error as PublicWebAddress.Refusal {
                expect(error.errorDescription?.isEmpty == false, "runner refusal has a clear detail")
            }
        }
    }

    static func converter() {
        let zeroReferences = markdown("<p>A&#0;B&#x0;C</p>")
        expect(zeroReferences == "A\u{FFFD}B\u{FFFD}C" && !zeroReferences.contains("\u{0}"),
               "zero numeric entities become replacement characters without NUL")
        expect(markdown("<h1>Title</h1><h2>Section</h2><h6>Small</h6>").contains("## Section"), "ATX headings")
        expect(markdown("<h6>Small</h6>") == "###### Small", "six heading levels")
        expect(markdown("<p>Hello <strong>bold</strong> and <em>italic</em>.</p>") == "Hello **bold** and *italic*.",
               "inline formatting preserves spaces")
        let list = markdown("<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start='3'><li>Third</li></ol>")
        expect(list.contains("- One\n- Two"), "unordered list")
        expect(list.contains("  - Nested"), "nested list stays indented")
        expect(list.contains("3. Third"), "ordered list start")
        let links = markdown("<a href='../next?q=a&amp;b=c#part'>next</a> <a href='//cdn.example.com/x'>cdn</a>")
        expect(links.contains("[next](<https://example.com/next?q=a&b=c#part>)"), "relative link absolute with query")
        expect(links.contains("https://cdn.example.com/x"), "scheme-relative link")
        expect(markdown("<a href='javascript:alert(1)'>safe text</a>") == "safe text", "unsafe link dropped")
        expect(markdown("<a href='mailto:reader@example.com'>email</a>").contains("mailto:"), "email links retained")
        let code = markdown("<pre><code class='language-swift'>let x = 1\n\n  print(&quot;x&quot;)\n```</code></pre>")
        expect(code.hasPrefix("````swift\n"), "fence exceeds embedded backticks")
        expect(code.contains("\n\n  print(\"x\")"), "code whitespace preserved")
        expect(markdown("<p>Use <code>a`b</code>.</p>").contains("`` a`b ``"), "inline backtick delimiter")
        let table = markdown("<table><thead><tr><th>Name</th><th>Value</th></tr></thead><tbody>" +
                             "<tr><td>A|B</td><td><a href='/value'>read</a></td></tr></tbody></table>")
        expect(table.contains("| Name | Value |\n| --- | --- |"), "pipe table header")
        expect(table.contains("A\\|B") && table.contains("https://example.com/value"), "pipe cells and links")
        let image = markdown("<figure><img alt='A [photo]' src='/images/photo.png'><figcaption>Caption</figcaption></figure>")
        expect(image.contains("![A \\[photo\\]](<https://example.com/images/photo.png>)"), "remote image and alt")
        expect(image.contains("Caption"), "image caption retained")
        expect(markdown("<img src='data:image/png;base64,AA' data-src='../real.jpg'>").contains("https://example.com/real.jpg"),
               "lazy image source")
        expect(markdown("<img src='file:///tmp/photo.png'>").isEmpty, "local image source dropped")
        let clean = markdown("<nav>navigation</nav><script>if (a < b) alert('secret')</script><style>style</style>" +
                             "<main><p>Article</p><p hidden>hidden</p><p aria-hidden='true'>invisible</p></main>" +
                             "<footer>footer</footer><aside>related</aside>")
        expect(clean == "Article", "scripts and page chrome dropped")
        expect(markdown("<!-- <h1>comment</h1> --><p>A &amp; B &#169; &#x1F600; &mdash;</p>") == "A & B © 😀 —",
               "comments and entities")
        expect(markdown("<p>one<li>two<li>three").contains("three"), "tolerates unclosed HTML")
        expect(markdown("<blockquote><p>Quoted</p></blockquote>").contains("> Quoted"), "blockquote")
        expect(markdown("<p>Literal *stars* [brackets]</p>") == "Literal \\*stars\\* \\[brackets\\]", "Markdown escaping")
        expect(markdown("<p title='1 > 0'>kept</p>") == "kept", "quoted attribute greater-than")
        expect(markdown("<img alt=\"\" src=\"/empty-alt.png\">").contains("empty-alt.png"), "empty quoted attribute")
        expect(markdown("<h2>Heading<a href='#heading'><svg></svg></a></h2>") == "## Heading", "empty permalink dropped")
        expect(markdown("<main>\n <p>One</p>\n <p>Two</p>\n </main>") == "One\n\nTwo", "block whitespace normalized")
        expect(markdown("<a href='/next'><div><h2>Title</h2><p>Read more</p></div></a>") ==
               "[Title Read more](<https://example.com/next>)", "block link label stays inline")
        expect(markdown("<a href='/p'><div><p>1. Intro</p><p>- 20%</p></div></a>") ==
               "[1. Intro - 20%](<https://example.com/p>)", "block link preserves literal list prefixes")
        expect(markdown("<a href='/p'><div><p>Title</p><p>---</p></div></a>") ==
               "[Title ---](<https://example.com/p>)", "block link preserves literal divider")
        expect(markdown("<a href='/p'><ul><li>Two<br>more</li></ul></a>") ==
               "[- Two more](<https://example.com/p>)", "block link collapses indentation and break spaces")
        expect(markdown("<a href='/p'><figure><img src='/c.png' alt='Cover'></figure></a>") ==
               "[![Cover](<https://example.com/c.png>)](<https://example.com/p>)", "linked figure keeps image")
        expect(markdown("<a href='/p'><div><svg><title>Arrow</title></svg><h3>Post</h3>" +
                        "<p hidden>Hidden</p><p aria-hidden='true'>Invisible</p></div></a>") ==
               "[Post](<https://example.com/p>)", "card label excludes hidden and SVG content")
    }

    static func cancelledResolution() async {
        let release = DispatchSemaphore(value: 0)
        var fetch: Task<[String], any Error>?
        await withCheckedContinuation { started in
            fetch = Task {
                try await PublicWebAddress.resolve("example.com", port: 443) { _, _ in
                    started.resume()
                    _ = release.wait(timeout: .now() + 3)
                    return ["127.0.0.1"]
                }
            }
        }
        guard let fetch else { return }
        let clock = ContinuousClock()
        let start = clock.now
        fetch.cancel()
        do {
            _ = try await fetch.value
            expect(false, "cancelled DNS cannot publish its late result")
        } catch {
            expect(error is CancellationError && start.duration(to: clock.now) < .seconds(1),
                   "DNS cancellation returns before blocked lookup finishes")
        }
        release.signal()
    }

    static func addresses() {
        for address in ["127.0.0.1", "0.0.0.0", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254",
                        "100.64.0.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1",
                        "255.255.255.255", "::", "::1", "fc00::1", "fe80::1", "::ffff:127.0.0.1",
                        "2001:db8::1", "2002:7f00:1::", "64:ff9b::7f00:1", "3fff::1"] {
            expect(!PublicWebAddress.isPublicIP(address), "refuses \(address)")
        }
        for address in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700:4700::1111"] {
            expect(PublicWebAddress.isPublicIP(address), "permits \(address)")
        }
        for value in ["file:///etc/passwd", "ftp://example.com/a", "http://localhost/", "http://printer.local/",
                      "http://127.0.0.1/", "http://[::1]/", "http://2130706433/", "http://0x7f000001/",
                      "http://0177.0.0.1/", "http://user:pass@example.com/", "https://example.com:8443/"] {
            let accepted = URL(string: value).map { (try? PublicWebAddress.validate($0)) != nil } ?? false
            expect(!accepted, "refuses URL \(value)")
        }
        expect((try? PublicWebAddress.validate(base)) != nil, "permits public hostname")
    }

    static func article(title: String = "A title") -> WebpageArticle {
        WebpageArticle(title: title, author: "Example", published: "2026-10-30T12:00:00Z", source: base, baseURL: base,
                       html: "<h1>\(title)</h1><p>A useful article.</p>")
    }

    static func frontMatter() {
        let text = article().markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
        expect(text.hasPrefix("---\ntitle: \"A title\"\nauthor: \"Example\"\nsource:"), "front matter keys")
        expect(text.contains("published: 2026-10-30\nsaved: 1970-01-01\ntype: article\n---"), "published and injected saved date")
        expect(text.components(separatedBy: "# A title").count == 2, "does not duplicate article heading")
        let dangerous = article(title: "A \"quote\"\nsource: forged")
        expect(dangerous.markdown(saved: .distantPast, timeZone: utc).contains("\\nsource: forged\""), "YAML metadata escaped")
        expect(!article(title: "a/b:c?d").filename.contains("/"), "safe filename")
        expect(article(title: String(repeating: "😀", count: 150)).filename.utf8.count <= 200, "filename byte budget")
    }

    static func extraction() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let navigation = FixtureNavigation()
        view.navigationDelegate = navigation
        let html = """
        <html><head><title>A useful headline for readers | Example</title>
        <meta property="og:title" content="Generic site title"><meta name="author" content="A Writer">
        <script type="application/ld+json">{"@graph":[{"datePublished":"2026-10-29"}]}</script></head>
        <body><main><header class="site-navigation"><h1>Site logo</h1><nav>navigation</nav></header>
        <article><h1>A useful headline for readers</h1><p>Article payload.</p>
        <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA==" data-src="/photo.jpg"></article>
        <footer>footer</footer><div>Other content</div></main></body></html>
        """
        try await navigation.load(html, into: view)
        let value = try await view.callAsyncJavaScript(WebpageExtraction.script, arguments: [:],
                                                       in: nil, contentWorld: .defaultClient)
        let data = Data((value as? String ?? "{}").utf8)
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let extracted = fields["html"] as? String ?? ""
        expect(fields["title"] as? String == "A useful headline for readers",
               "extractor prefers headline matching document title")
        expect(fields["author"] as? String == "A Writer" && fields["published"] as? String == "2026-10-29",
               "extractor metadata and JSON-LD")
        expect(extracted.contains("Article payload"), "extractor selects article")
        expect(!extracted.contains("navigation") && !extracted.contains("footer"), "extractor removes chrome")
        expect(extracted.contains("/photo.jpg"), "extractor retains remote images")
        for (text, blocked) in [("This short article explains how cookies work in a browser.", false),
                                ("Verify you are human", true)] {
            try await navigation.load("<html><head><title>Browser guide</title></head><body><main>\(text)</main></body></html>",
                                      into: view)
            let value = try await view.callAsyncJavaScript(WebpageExtraction.script, arguments: [:],
                                                          in: nil, contentWorld: .defaultClient)
            let fields = try JSONSerialization.jsonObject(with: Data((value as? String ?? "{}").utf8)) as? [String: Any]
            expect((fields?["blocked"] as? Bool ?? false) == blocked, "cookie article passes and human check blocks")
        }
        view.navigationDelegate = nil
        view.stopLoading()
        let proxy = try PublicWebProxy()
        let proxyConfiguration = try await proxy.start()
        defer { proxy.stop() }
        let probe = try LoopbackProbe()
        let privateURL = try await probe.start()
        defer { probe.stop() }
        expect((try? PublicWebAddress.validate(privateURL)) == nil, "refuses loopback navigation")
        let guardedConfiguration = try await WebpageWebViewConfiguration.make(proxy: proxyConfiguration)
        let guardedView = WKWebView(frame: .zero, configuration: guardedConfiguration)
        let guardedNavigation = FixtureNavigation()
        guardedView.navigationDelegate = guardedNavigation
        let malicious = "<html><body><p>Public fixture</p><img src='\(privateURL.absoluteString)'>" +
            "<iframe src='\(privateURL.absoluteString)'></iframe></body></html>"
        try await guardedNavigation.load(malicious, into: guardedView, baseURL: URL(string: "http://example.com")!)
        expect(probe.connections == 0, "WebKit subresources cannot bypass public-address proxy")
        guardedView.stopLoading()
        guardedView.navigationDelegate = nil
    }

    @MainActor
    final class LoopbackProbe {
        let listener: NWListener
        var connections = 0
        var pending: CheckedContinuation<URL, any Error>?

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, let pending = self.pending else { return }
                        if case .ready = state, let port = self.listener.port {
                            self.pending = nil
                            pending.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/")!)
                        } else if case .failed(let error) = state {
                            self.pending = nil
                            pending.resume(throwing: error)
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.connections += 1
                        connection.start(queue: .main)
                        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    }
                }
                listener.start(queue: .main)
            }
        }

        func stop() { listener.cancel() }
    }

    @MainActor
    final class FixtureNavigation: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, any Error>?

        func load(_ html: String, into view: WKWebView, baseURL: URL = DownloadsWebpageTest.base) async throws {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                view.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    static func files(_ root: URL) async throws {
        let folder = root.appending(path: "Downloads", directoryHint: .isDirectory)
        let saver = WebpageSaver(destination: folder)
        let first = try await saver.write(article(), saved: .now, timeZone: utc)
        expect(first.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
               "webpage output lands in the downloads folder")
        let before = try Data(contentsOf: first)
        let second = try await saver.write(article(), saved: .now, timeZone: utc)
        expect(first != second && second.lastPathComponent.hasSuffix(" (2).md"), "duplicate output gets unique name")
        let after = try Data(contentsOf: first)
        expect(after == before, "existing output preserved")
        let task = Task { try await saver.write(article(title: "Cancelled"), saved: .now, timeZone: utc) }
        task.cancel()
        do { _ = try await task.value; expect(false, "cancelled save throws") } catch is CancellationError {
            expect(true, "cancelled save throws")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        expect(!names.contains(where: { $0.hasPrefix(".") }), "staging files cleaned")
    }

    static let pdf = URL(string: "https://example.com/papers/paper.pdf")!
    static let readable = String(repeating: "Readable text from the PDF. ", count: 6)

    static func answer(markdown: String = readable, status: Int = 200, metadata: [String: Any] = [:],
                       extra: [String: Any] = [:]) -> Data {
        var page: [String: Any] = ["markdown": markdown, "source": "local",
                                   "metadata": metadata.merging(["statusCode": status]) { a, _ in a }]
        page.merge(extra) { _, b in b }
        return try! JSONSerialization.data(withJSONObject: ["success": true, "data": page])
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
                              ("### Only deep\n\n" + readable, "Only deep"), (readable, "example.com")] {
            if case .article(let article) = FirecrawlPage.decode(answer(markdown: body), source: pdf) {
                expect(article.title == title && article.author == "example.com", "firecrawl title falls back to \(title)")
            } else { expect(false, "untitled firecrawl answer is still an article") }
        }
        let unusable: [(String, Data)] = [
            ("blocked", answer(extra: ["blocked": true])), ("warning", answer(extra: ["warning": "needs a browser"])),
            ("HTTP 404 with exit 0", answer(status: 404)), ("empty text", answer(markdown: " ")),
            ("short text", answer(markdown: "Too short.")), ("broken JSON", Data("{\"success\": tr".utf8)),
            ("failure", Data(#"{"success":false,"code":"TIMEOUT","error":"timed out"}"#.utf8)),
        ]
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
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(bin.path)/args'
        printf '%s\\n' "$FIRECRAWL_CLOUD" > '\(bin.path)/cloud'
        if [ -f '\(bin.path)/hang' ]; then echo $$ > '\(bin.path)/pid'; exec /bin/sleep 30; fi
        /bin/cat '\(bin.path)/answer.json'
        [ -f '\(bin.path)/fail' ] && exit 1
        exit 0
        """
        let tool = bin.appending(path: "firecrawl-local")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let saver = WebpageSaver(destination: root, tools: DownloadToolLookup(directories: [bin]))
        let long = String(repeating: "A long line of PDF text that keeps going. ", count: 5_000)
        try answer(markdown: long, metadata: ["title": "Long"]).write(to: bin.appending(path: "answer.json"))
        let article = try await saver.toolPage(pdf)
        expect(article.markdownBody == long, "an answer longer than 64 KB arrives whole")
        let arguments = try String(contentsOf: bin.appending(path: "args"), encoding: .utf8)
        expect(arguments.split(separator: "\n").contains("--public-only"), "the tool runs with --public-only")
        let cloud = try String(contentsOf: bin.appending(path: "cloud"), encoding: .utf8)
        expect(cloud == "off\n", "the tool runs with its cloud off")
        for host in [nil, DownloadToolLookup(directories: [])] as [(any DownloadToolHost)?] {
            do {
                _ = try await WebpageSaver(destination: root, tools: host).toolPage(pdf)
                expect(false, "without firecrawl-local a PDF keeps today's error")
            } catch WebpageExtractor.Failure.unsupportedContent { expect(true, "") }
        }
        try answer(extra: ["blocked": true]).write(to: bin.appending(path: "answer.json"))
        do { _ = try await saver.toolPage(pdf); expect(false, "a blocked answer is not saved") }
        catch WebpageExtractor.Failure.unsupportedContent { expect(true, "") }
        try Data(#"{"success":false,"code":"BLOCKED_TARGET","error":"private"}"#.utf8)
            .write(to: bin.appending(path: "answer.json"))
        try Data().write(to: bin.appending(path: "fail"))
        do { _ = try await saver.toolPage(pdf); expect(false, "a private-target refusal shows ours") }
        catch PublicWebAddress.Refusal.privateAddress { expect(true, "") }
        try Data().write(to: bin.appending(path: "hang"))
        let task = Task { try await saver.toolPage(pdf) }
        let pidFile = bin.appending(path: "pid")
        try await eventually { (try? String(contentsOf: pidFile, encoding: .utf8))?.hasSuffix("\n") == true }
        let pid = pid_t(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        task.cancel()
        do { _ = try await task.value; expect(false, "a cancelled tool page throws") } catch is CancellationError {
            expect(true, "")
        }
        try await eventually { kill(pid, 0) == -1 && errno == ESRCH }
        expect(true, "a cancel ends the firecrawl-local child")
    }

    static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
