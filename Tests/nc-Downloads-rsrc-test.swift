// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/CaptionText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/FirecrawlPage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/RsrcPage.swift
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
struct DownloadsRsrcTest {
    static var passes = 0
    static var failures = 0
    static let thread = URL(string: "https://x.com/somebody/status/2126281598517576049")!
    static let reddit = URL(string: "https://www.reddit.com/r/swift/comments/1abcde/a_question/")!
    static let hackerNews = URL(string: "https://news.ycombinator.com/item?id=48734373")!
    static let linkedIn = URL(string: "https://www.linkedin.com/posts/somebody_a-post-activity-7204256477832753153-1shK/")!
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-rsrc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        requests()
        threads()
        discussions()
        try await tool(root)
        try await deadline(root)
        print("Downloads rsrc: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func item(_ text: String?, author: String? = "somebody", title: String? = nil,
                     published: String = "2026-11-27T11:46:52Z", raw: [String: Any] = [:]) -> [String: Any] {
        ["text": text ?? NSNull(), "author": author ?? NSNull(), "title": title ?? NSNull(),
         "published_at": published, "raw": raw]
    }

    static func answer(_ items: [[String: Any]], ok: Bool = true) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": ok, "items": items, "error": NSNull()])) ?? Data()
    }

    static func requests() {
        let asked: [(URL, [String])] = [
            (thread, ["x", "thread", thread.absoluteString]),
            (URL(string: "https://twitter.com/somebody/status/1")!, ["x", "thread", "https://twitter.com/somebody/status/1"]),
            (reddit, ["reddit", "read", reddit.absoluteString, "--comments", "50", "--backend", "arctic-shift"]),
            (hackerNews, ["hn", "read", hackerNews.absoluteString, "--comments", "50"]),
            (linkedIn, ["linkedin", "read", linkedIn.absoluteString]),
            (URL(string: "https://www.linkedin.com/feed/update/urn:li:activity:7204256477832753153/")!,
             ["linkedin", "read", "https://www.linkedin.com/feed/update/urn:li:activity:7204256477832753153/"]),
        ]
        for (url, arguments) in asked {
            expect(RsrcPage.request(url)?.arguments == arguments, "rsrc is asked for \(url.absoluteString)")
        }
        for link in ["https://example.com/articles/page", "https://x.com/somebody", "https://www.reddit.com/r/swift/",
                     "https://news.ycombinator.com/", "https://www.linkedin.com/in/somebody/",
                     "https://notreddit.com/r/swift/comments/1abcde/", "ftp://x.com/somebody/status/1"] {
            expect(RsrcPage.request(URL(string: link)!) == nil, "rsrc is not asked for \(link)")
        }
    }

    static func threads() {
        let quoted: [String: Any] = ["author": "other", "text": "The quoted post.\nSecond line.",
                                     "media": [["type": "photo", "url": "https://img.example/q.jpg"]]]
        let posts = [
            item("First post of the thread.\n\nIts second paragraph.", raw: ["quoted": quoted]),
            item("Second post.", raw: ["media": [["type": "photo", "url": "https://img.example/a.jpg"],
                                                 ["type": "video", "url": "https://video.example/b.mp4"],
                                                 ["type": "photo", "url": "javascript:alert(1)"]]]),
            item("Third post."),
        ]
        guard let article = RsrcPage.decode(answer(posts), site: .x, source: thread) else {
            expect(false, "a thread of three posts is an article")
            return
        }
        let text = article.markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
        expect(article.title == "First post of the thread." && article.author == "somebody",
               "a thread is named by its first line and its author")
        expect(text.contains("published: 2026-11-27"), "a thread carries the first post's day")
        let quote = "> @other\n>\n> The quoted post.  \n> Second line.\n>\n> ![](<https://img.example/q.jpg>)"
        expect(text.contains("Its second paragraph.\n\n\(quote)\n\nSecond post."),
               "a quoted post is a block quote under its post")
        expect(text.contains("Second post.\n\n![](<https://img.example/a.jpg>)\n\n<https://video.example/b.mp4>\n\nThird post."),
               "photos are images, other media are links, and posts keep their order")
        expect(!text.contains("javascript:"), "a media address that is not https is left out")

        let linked: [String: Any] = ["author": "other", "id": "2126161398187389140", "text": "Quoted."]
        let hostile = [
            item("One <img src=\"https://bad.example/p.gif\"> two.\n"
                 + "[open](obsidian://run) [js](&#106;avascript:x) [ok](https://ok.example)",
                 raw: ["quoted": linked, "media": [["type": "photo", "url": "https://img.example/a.jpg)[x](<b>"]]]),
            item("[ref]: javascript:alert(1)\nAfter."),
        ]
        let note = RsrcPage.decode(answer(hostile), site: .x, source: thread)?
            .markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc) ?? ""
        // The front matter and the heading come first; `WebpageArticle` quotes and escapes the title in them.
        let guarded = note.components(separatedBy: "\n\n").dropFirst(2).joined(separator: "\n\n")
        expect(note.contains("\n# One \\<img") && guarded.contains("One &lt;img src=") && !guarded.contains("<img"),
               "raw HTML in a post is written as text")
        expect(guarded.contains("[open]\\(obsidian://run) [js]\\(&#106;avascript:x) [ok](https://ok.example)"),
               "a link that leaves the web is written as text, a web link is kept")
        expect(guarded.contains("\\[ref]: javascript:alert(1)  \nAfter."), "a link definition is written as text")
        expect(guarded.contains("![](<https://img.example/a.jpg)%5Bx%5D(%3Cb%3E>)"), "a media address cannot close its own link")
        expect(guarded.contains("> [@other](https://x.com/other/status/2126161398187389140)\n>\n> Quoted."),
               "a quoted post links to itself")

        let long = String(repeating: "word ", count: 30)
        let untitled = RsrcPage.decode(answer([item(long), item("More.")]), site: .x, source: thread)
        expect(untitled?.title.count ?? 0 <= 81 && untitled?.title.hasSuffix("…") == true, "a long first line is cut at a word")

        let refused: [(String, Data, Int32)] = [
            ("one post", answer([item("Alone.")]), 0), ("no items", answer([]), 0),
            ("a failed run", answer(posts, ok: false), 0), ("a nonzero exit", answer(posts), 1),
            ("broken JSON", Data("{\"ok\": tr".utf8), 0), ("posts without text", answer([item(nil), item(nil)]), 0),
        ]
        for (name, data, status) in refused {
            expect(RsrcPage.decode(data, status: status, site: .x, source: thread) == nil, "\(name) is left to the post reader")
        }
    }

    static func discussions() {
        let story = item(nil, author: "poster", title: "A story", raw: ["item": ["url": "https://example.com/story"]])
        let comments = [
            item("Top comment.", author: "first", published: "2026-06-30T16:03:26Z",
                 raw: ["item": ["id": 2, "parent_id": 1]]),
            item("A reply.\nOn two lines.", author: "second", published: "2026-06-30T16:07:25Z",
                 raw: ["item": ["id": 3, "parent_id": 2]]),
            item(nil, author: "empty", raw: ["item": ["id": 4, "parent_id": 1]]),
            item("Another top comment.", author: nil, raw: ["item": ["id": 5, "parent_id": 1]]),
        ]
        if let article = RsrcPage.decode(answer([story] + comments), site: .hackerNews, source: hackerNews) {
            let text = article.markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
            expect(article.title == "A story" && article.author == "poster", "a story keeps its title and poster")
            expect(text.contains("<https://example.com/story>\n\n## Comments\n\n**first** · 2026-06-30\n\nTop comment."),
                   "a story links what it is about, then lists its comments")
            expect(text.contains("> **second** · 2026-06-30\n>\n> A reply.\n> On two lines.\n\n**[deleted]**"),
                   "a reply is quoted under its parent and a comment without text is left out")
        } else { expect(false, "a Hacker News story is an article") }

        func attrs(_ id: String, under parent: String) -> [String: Any] { ["attrs": ["thingid": id, "parentid": parent]] }
        let post = item("The question.", author: nil, title: nil, raw: ["attrs": ["id": "t3_post"]])
        let replies = [item("A follow-up.", author: "asker", raw: attrs("t1_b", under: "t1_a")),
                       item("An answer.", author: "helper", raw: attrs("t1_a", under: "t3_post")),
                       item("A late reply.", author: "third", raw: attrs("t1_c", under: "t1_b")),
                       item("Its parent was not returned.", author: "orphan", raw: attrs("t1_e", under: "t1_d")),
                       item("Loop one.", author: "loop", raw: attrs("t1_f", under: "t1_g")),
                       item("Loop two.", author: "loop", raw: attrs("t1_g", under: "t1_f"))]
        if let article = RsrcPage.decode(answer([post] + replies), site: .reddit, source: reddit) {
            let text = article.markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
            expect(article.title == "The question." && article.author == "www.reddit.com",
                   "a post without title or author is named by its text and its site")
            expect(text.contains("**helper** · 2026-11-27\n\nAn answer.\n\n> **asker** · 2026-11-27\n>\n> A follow-up.\n\n"
                                 + "> > **third** · 2026-11-27\n> >\n> > A late reply.\n\n**orphan**"),
                   "a Reddit reply listed before its parent is moved under it, and one without its parent stays on top")
            expect(text.contains("**loop** · 2026-11-27\n\nLoop one.\n\n**loop** · 2026-11-27\n\nLoop two."),
                   "comments that only name each other are kept, flat")
        } else { expect(false, "a Reddit post is an article") }

        let update = item("We shipped.", author: "A Company", title: "We shipped.")
        if let article = RsrcPage.decode(answer([update, item("Congratulations!", author: "A Friend")]),
                                         site: .linkedIn, source: linkedIn) {
            let text = article.markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc)
            expect(text.contains("We shipped.\n\n## Comments\n\n**A Friend** · 2026-11-27\n\nCongratulations!"),
                   "LinkedIn comments, which carry no depth, are listed flat")
        } else { expect(false, "a LinkedIn post is an article") }
        expect(RsrcPage.decode(answer([update]), site: .linkedIn, source: linkedIn) != nil, "a post without comments is saved")
        let lined = [item("Line one.\nLine two.\n\nNext."), item("<b>Hi</b>", author: "A <i>B</i>\nC")]
        let plain = RsrcPage.decode(answer(lined), site: .linkedIn, source: linkedIn)?
            .markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc) ?? ""
        expect(plain.contains("Line one.  \nLine two.\n\nNext.\n\n## Comments\n\n"
                              + "**A &lt;i>B&lt;/i> C** · 2026-11-27\n\n&lt;b>Hi&lt;/b>"),
               "plain text keeps its line ends, and a comment's author and text carry no HTML")

        var chain = [item("Self.", author: "self", raw: ["item": ["id": 1, "parent_id": 1]])]
        chain += (2...9).map { item("Level \($0).", author: "deep", raw: ["item": ["id": $0, "parent_id": $0 - 1]]) }
        chain.append(item("Twin.", author: "twin", raw: ["item": ["id": 9, "parent_id": 8]]))
        let deep = RsrcPage.decode(answer([story] + chain), site: .hackerNews, source: hackerNews)?
            .markdown(saved: Date(timeIntervalSince1970: 0), timeZone: utc) ?? ""
        expect(deep.contains("**self** · 2026-11-27\n\nSelf.\n\n> **deep**"),
               "a comment that names itself as parent stays on top")
        expect(deep.contains("> > > > > > Level 9.") && !deep.contains("> > > > > > > "), "nesting stops at six levels")
        expect(deep.components(separatedBy: "Twin.").count == 2 && deep.components(separatedBy: "Level 9.").count == 2,
               "comments that share an id are each written once")
        expect(RsrcPage.decode(answer([item(nil)]), site: .reddit, source: reddit) == nil,
               "a post with no text and no comments is left to the page reader")
    }

    static func read(_ file: URL) -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }

    static func page() -> WebpageExtractor.Page {
        .article(WebpageArticle(title: "Page reader", author: "Author", published: nil,
                                source: reddit, baseURL: reddit, html: "<p>From the page reader.</p>"))
    }

    static func tool(_ root: URL) async throws {
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        let files = root.appending(path: "output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(bin.path)/args'
        /bin/cat '\(bin.path)/answer.json'
        [ -f '\(bin.path)/fail' ] && exit 1
        exit 0
        """
        let tool = bin.appending(path: "rsrc")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let saver = WebpageSaver(destination: files, tools: DownloadToolLookup(directories: [bin]))
        let args = bin.appending(path: "args")
        let output = bin.appending(path: "answer.json")
        let fail = bin.appending(path: "fail")

        try answer([item("First post."), item("Second post.")]).write(to: output)
        let saved = try await saver.save(thread) { _ in
            expect(false, "a thread rsrc read never reaches the page reader")
            return page()
        }
        let markdown = read(saved)
        expect(markdown.contains("First post.\n\nSecond post."), "the whole thread is saved in one file")
        expect(saved.lastPathComponent == "somebody - First post.md", "a thread keeps the usual file name")
        expect(read(args).split(separator: "\n").map(String.init)
               == ["x", "thread", thread.absoluteString], "the tool is asked for the thread behind the link")
        try FileManager.default.removeItem(at: saved)

        try answer([item("The question.", title: "A question"), item("An answer.", author: "helper")]).write(to: output)
        let discussion = try await saver.save(reddit) { _ in page() }
        expect(read(discussion).contains("## Comments\n\n**helper**"),
               "a Reddit link is saved with its comments")
        try FileManager.default.removeItem(at: discussion)

        try Data().write(to: fail)
        let failed = try await saver.save(reddit) { _ in page() }
        expect(read(failed).contains("From the page reader."),
               "a failed run falls back to the page reader")
        try FileManager.default.removeItem(at: failed)
        try FileManager.default.removeItem(at: fail)

        try FileManager.default.removeItem(at: args)
        let plain = try await saver.save(URL(string: "https://example.com/articles/page")!) { _ in page() }
        expect(!FileManager.default.fileExists(atPath: args.path), "another site never starts the tool")
        try FileManager.default.removeItem(at: plain)

        for host in [nil, DownloadToolLookup(directories: [])] as [(any DownloadToolHost)?] {
            let without = try await WebpageSaver(destination: files, tools: host).save(reddit) { _ in page() }
            expect(read(without).contains("From the page reader."),
                   "without rsrc the link is saved as before")
            try FileManager.default.removeItem(at: without)
        }
    }

    static func deadline(_ root: URL) async throws {
        let destination = root.appending(path: "timeout-output")
        let child = HangingTool()
        let saver = WebpageSaver(destination: destination, tools: child, waitForDeadline: {
            var events = child.started.stream.makeAsyncIterator()
            _ = await events.next()
        })
        let late = try await saver.save(reddit) { _ in page() }
        expect(child.stopped.withLock { $0 }, "the deadline awaits child cancellation")
        expect(read(late).contains("From the page reader."),
               "a run past its deadline falls back to the page reader")
        try FileManager.default.removeItem(at: destination)

        let cancelled = HangingTool()
        let task = Task {
            try await WebpageSaver(destination: destination, tools: cancelled).save(reddit) { _ in
                expect(false, "a cancelled save never reaches the page reader")
                return page()
            }
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
        expect(!FileManager.default.fileExists(atPath: destination.path), "a cancelled save writes no file")
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
