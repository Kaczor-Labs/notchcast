// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillDrop.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillNote.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillTranscript.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLMarkdown.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageArticle.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageExtraction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/YtDlpAudio.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillNotes.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebAddress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebProxy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
import Foundation

/// Distill's Markdown folder: front matter, names that never overwrite, which dropped files convert, and
/// pages, transcripts and dropped files reaching the folder while each original stays where it is.
@main
@MainActor
struct DownloadsNotesTest {
    static let saved = Date(timeIntervalSince1970: 1_763_424_000)
    static let utc = TimeZone(identifier: "UTC")!

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "nc-downloads-notes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        frontMatter()
        drops()
        try naming(root)
        try await webpages(root)
        try await transcript(root)
        try await droppedFiles(root)
        print("Downloads notes: front matter, numbered names, dropped-file choice; pages, transcripts and "
              + "dropped files reach the Markdown folder")
    }

    private static func frontMatter() {
        let text = DistillNote.markdown(title: "Talk: \"One\"", source: "https://example.com/a/b", saved: saved,
                                        timeZone: utc, body: "\nhello\n\n")
        let expected = "---\ntitle: \"Talk: \\\"One\\\"\"\nsource: \"https://example.com/a/b\"\n"
            + "saved: 2025-11-18\n---\n\nhello\n"
        expect(text == expected, "front matter holds title, source and day, then the text: \(text)")
        let west = DistillNote.markdown(title: "t", source: "s", saved: saved,
                                        timeZone: TimeZone(secondsFromGMT: -3600)!, body: "b")
        expect(west.contains("saved: 2025-11-17\n"), "the day is the user's own")
    }

    private static func drops() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-60)
        func entry(_ name: String, regular: Bool = true, link: Bool = false, modified: Date? = nil) -> DistillDrop.Entry {
            .init(path: "/notes/" + name, isRegularFile: regular, isSymbolicLink: link, modified: modified ?? old)
        }
        func job(_ name: String, _ state: DownloadState) -> DownloadJob {
            DownloadJob(id: name, kind: "distill", source: "/notes/" + name, title: name, state: state, created: old)
        }
        let entries = [
            entry("b.pdf"), entry("a.html"), entry("talk.MP3"), entry("note.md"), entry(".hidden.pdf"),
            entry(".A1B2.partial"), entry("half.pdf.crdownload"), entry("linked.pdf", regular: false, link: true),
            entry("folder.pdf", regular: false), entry("fresh.m4a", modified: now.addingTimeInterval(-2)),
            entry("queued.pdf"), entry("failed.pdf"), entry("done.pdf"), entry("readme.txt"),
        ]
        let jobs = [job("queued.pdf", .waiting), job("failed.pdf", .failed), job("done.pdf", .done)]
        let plan = DistillDrop.plan(entries, jobs: jobs, now: now, retryFailed: false)
        expect(plan.sources == ["/notes/a.html", "/notes/b.pdf", "/notes/done.pdf", "/notes/talk.MP3"],
               "PDF, HTML and audio convert in name order; Markdown, hidden, partial, symlinked, queued and "
               + "failed files do not: \(plan.sources)")
        expect(plan.recheck == now.addingTimeInterval(3), "a file still arriving is looked at again once it settles")
        let retry = DistillDrop.plan(entries, jobs: jobs, now: now, retryFailed: true)
        expect(retry.sources.contains("/notes/failed.pdf") && !retry.sources.contains("/notes/queued.pdf"),
               "Run Distill retries a failed file, never one already queued")
        expect(DistillDrop.plan(entries, jobs: [], now: now.addingTimeInterval(10), retryFailed: false).recheck == nil,
               "nothing settling, nothing to look at again")
        expect(DistillDrop.kind(of: "x.HTM") == .html && DistillDrop.kind(of: "x.md") == nil
               && DistillDrop.kind(of: "x.mov") == .media, "kinds follow the extension, any case")
    }

    private static func naming(_ root: URL) throws {
        let notes = DistillNotes(folder: root.appending(path: "names", directoryHint: .isDirectory), saved: saved,
                                 timeZone: utc)
        let first = try notes.write(title: "Same", source: "a", stem: "Same", body: "one")
        let second = try notes.write(title: "Same", source: "b", stem: "Same", body: "two")
        expect(first.lastPathComponent == "Same.md" && second.lastPathComponent == "Same (2).md",
               "a taken name gets a number")
        try expect(String(contentsOf: first, encoding: .utf8).hasSuffix("\none\n")
                   && String(contentsOf: second, encoding: .utf8).hasSuffix("\ntwo\n"), "no note is overwritten")
    }

    /// Acceptance 1 and 2: each saved page lands once in the folder with its front matter, same titles both kept.
    private static func webpages(_ root: URL) async throws {
        let raw = root.appending(path: "pages/Raw", directoryHint: .isDirectory)
        let folder = root.appending(path: "pages/Notes", directoryHint: .isDirectory)
        let notes = DistillNotes(folder: folder, saved: saved, timeZone: utc)
        var pages: [URL] = []
        for path in ["one", "two"] {
            let source = URL(string: "https://example.com/\(path)")!
            let article = WebpageArticle(title: "Same Title", author: "Ann", published: nil, source: source,
                                         baseURL: source, html: "<p>Body \(path)</p>")
            let page = try await WebpageSaver(destination: raw).write(article, saved: saved, timeZone: utc)
            _ = try notes.copy(page)
            pages.append(page)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        expect(names == ["Ann - Same Title (2).md", "Ann - Same Title.md"], "two pages, one title: two notes: \(names)")
        for (index, path) in ["one", "two"].enumerated() {
            let note = try String(contentsOf: folder.appending(path: names[1 - index]), encoding: .utf8)
            expect(note.hasPrefix("---\ntitle: \"Same Title\"\n") && note.contains("source: \"https://example.com/\(path)\"\n")
                   && note.contains("saved: 2025-11-18\n") && note.contains("Body \(path)"),
                   "a page's note carries its front matter and text: \(note)")
            expect(FileManager.default.fileExists(atPath: pages[index].path), "the saved page stays where it is")
        }
    }

    private static func transcript(_ root: URL) async throws {
        let folder = root.appending(path: "media/Notes", directoryHint: .isDirectory)
        let context = DownloadRunContext(destination: root.appending(path: "media/Raw", directoryHint: .isDirectory),
                                         tools: FakeTools())
        let runner = runner(root, notes: DistillNotes(folder: folder, saved: saved, timeZone: utc))
        let link = "https://www.youtube.com/watch?v=one"
        let output = try await runner.run(job(link), context: context)
        expect(output?.lastPathComponent == "Chan - Talk - One.txt", "the transcript still lands in the Distill folder")
        let note = try String(contentsOf: folder.appending(path: "Chan - Talk - One.md"), encoding: .utf8)
        expect(note == "---\ntitle: \"Talk: One\"\nsource: \"\(link)\"\nsaved: 2025-11-18\n---\n\nhello\nhello\n",
               "a transcript's note names its title and link: \(note)")
    }

    private static func droppedFiles(_ root: URL) async throws {
        let folder = root.appending(path: "drops/Notes", directoryHint: .isDirectory)
        let bin = root.appending(path: "drops/Trash", directoryHint: .isDirectory)
        for directory in [folder, bin] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var notes = DistillNotes(folder: folder, saved: saved, timeZone: utc)
        notes.trash = { try FileManager.default.moveItem(at: $0, to: bin.appending(path: $0.lastPathComponent)) }
        let context = DownloadRunContext(destination: root.appending(path: "drops/Raw", directoryHint: .isDirectory),
                                         tools: FakeTools())
        let busy = Counter()
        let runner = runner(root, notes: notes, busy: busy)

        let page = folder.appending(path: "page.html")
        try Data("<html><body><h1>Head</h1><p>Body text</p></body></html>".utf8).write(to: page)
        let pageNote = try await runner.run(job(page.path), context: context)
        expect(pageNote == folder.appending(path: "page.md"), "an HTML file becomes a note beside where it was")
        let text = try String(contentsOf: folder.appending(path: "page.md"), encoding: .utf8)
        expect(text.hasPrefix("---\ntitle: \"page\"\nsource: \"page.html\"\nsaved: 2025-11-18\n---\n\n")
               && text.contains("Body text"), "its note names the file it came from: \(text)")
        expect(!FileManager.default.fileExists(atPath: page.path)
               && FileManager.default.fileExists(atPath: bin.appending(path: "page.html").path),
               "the converted original goes to the Trash")

        let audio = folder.appending(path: "talk.mp3")
        try Data("audio".utf8).write(to: audio)
        _ = try await runner.run(job(audio.path), context: context)
        try expect(String(contentsOf: folder.appending(path: "talk.md"), encoding: .utf8).hasSuffix("\n\nhello\nhello\n"),
                   "an audio file becomes its transcript")

        let linked = folder.appending(path: "linked.html")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: bin.appending(path: "page.html"))
        await expectFailure(.unsupported, "a symlink is never converted") {
            _ = try await runner.run(job(linked.path), context: context)
        }
        await expectFailure(.noFolder, "a dropped file with no Markdown folder set fails plainly") {
            _ = try await Self.runner(root, notes: nil).run(job(audio.path), context: context)
        }

        let quiet = folder.appending(path: "quiet.mp3")
        try Data("audio".utf8).write(to: quiet)
        let refused = Self.runner(root, notes: notes, busy: busy, transcribe: { _ in throw NotchcastTranscribeError.busy })
        await expectFailure(.busy, "busy fails the file") { _ = try await refused.run(job(quiet.path), context: context) }
        expect(busy.count == 1 && FileManager.default.fileExists(atPath: quiet.path),
               "busy ends the run and keeps the file for Run Distill")
    }

    private static func runner(
        _ root: URL, notes: DistillNotes?, busy: Counter = Counter(),
        transcribe: @escaping DistillRunner.Transcribe = { _ in "hello" }
    ) -> DistillRunner {
        DistillRunner(workDirectory: root.appending(path: "work", directoryHint: .isDirectory), transcribe: transcribe,
                      timestamps: { false }, onBusy: { busy.count += 1 }, notes: { notes })
    }

    private static func job(_ source: String) -> DownloadJob {
        DownloadJob(id: UUID().uuidString, kind: DistillRunner.kind, source: source, title: source, created: saved)
    }

    private static func expectFailure(
        _ failure: DistillFailure, _ message: String, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            preconditionFailure(message + ": it succeeded")
        } catch {
            expect(error as? DistillFailure == failure, message + ": \(error)")
        }
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }
}

@MainActor
private final class Counter {
    var count = 0
}

/// Stands in for yt-dlp and ffmpeg: metadata, one audio file, then two chunks.
private struct FakeTools: DownloadToolHost {
    func find(_ tool: DownloadTool) -> URL? { URL(filePath: "/fake/" + tool.name) }

    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult {
        var output = ""
        if executable.lastPathComponent == "yt-dlp" {
            if arguments.contains("--skip-download") {
                output = #"{"id":"v","title":"Talk: One","channel":"Chan"}"#
            } else if let index = arguments.firstIndex(of: "-o") {
                let file = arguments[index + 1].replacingOccurrences(of: "%(ext)s", with: "m4a")
                try Data("audio".utf8).write(to: URL(filePath: file))
            }
        } else if let pattern = arguments.last {
            for index in 0..<2 { try Data("wav".utf8).write(to: URL(filePath: String(format: pattern, index))) }
        }
        return DownloadProcessResult(status: 0, output: output, errors: "")
    }
}
