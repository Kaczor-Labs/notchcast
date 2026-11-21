// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillDrop.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillNote.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillTranscript.swift
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
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/YtDlpAudio.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
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
        func stamp(_ name: String, size: UInt64 = 10) -> DistillDrop.Stamp {
            .init(file: name.utf8.reduce(0) { $0 &* 31 &+ UInt64($1) }, size: size, modified: old)
        }
        func entry(_ name: String, missing: Bool = false, as other: DistillDrop.Stamp? = nil) -> DistillDrop.Entry {
            .init(path: "/notes/" + name, stamp: missing ? nil : other ?? stamp(name))
        }
        func job(_ name: String, _ state: DownloadState) -> DownloadJob {
            DownloadJob(id: name, kind: "distill", source: "/notes/" + name, title: name, state: state, created: old,
                        encodedOptions: try? DownloadJob.encode(stamp(name)))
        }
        let entries = [
            entry("b.pdf"), entry("a.html"), entry("talk.MP3"), entry("note.md"), entry(".hidden.pdf"),
            entry(".A1B2.partial"), entry("half.pdf.crdownload"), entry("linked.pdf", missing: true),
            entry("no-date.pdf", missing: true),
            entry("queued.pdf"), entry("failed.pdf"), entry("done.pdf"), entry("readme.txt"),
        ]
        let jobs = [job("queued.pdf", .waiting), job("failed.pdf", .failed), job("done.pdf", .done)]
        let settle = DistillDrop.settle
        let settled = now.addingTimeInterval(settle)
        func plan(
            _ entries: [DistillDrop.Entry], _ jobs: [DownloadJob], seen: [String: DistillDrop.Sighting] = [:],
            existing: [String: UInt64]? = [:], at time: Date, retryFailed: Bool = false
        ) -> DistillDrop.Plan {
            DistillDrop.plan(entries, jobs: jobs, seen: seen, existing: existing, now: time, retryFailed: retryFailed)
        }
        expect(settle >= 30, "a copy that stalls for a few seconds is not taken for a whole file")
        let first = plan(entries, jobs, at: now)
        expect(first.ready.isEmpty && first.recheck == settled,
               "an old modification date alone is not settled: the first look only remembers")
        let early = plan(entries, jobs, seen: first.seen, at: settled.addingTimeInterval(-1))
        expect(early.ready.isEmpty && early.recheck == settled, "a look before the settle time is too soon")
        let second = plan(entries, jobs, seen: first.seen, at: settled)
        let sources = second.ready.map(\.path)
        expect(sources == ["/notes/a.html", "/notes/b.pdf", "/notes/done.pdf", "/notes/talk.MP3"]
               && second.ready.allSatisfy { $0.stamp == stamp(URL(filePath: $0.path).lastPathComponent) },
               "PDF, HTML, audio and video unchanged across two looks convert in name order with their stamp; Markdown, "
               + "hidden, partial, symlinked, dateless, queued and failed files do not: \(sources)")
        expect(second.recheck == nil, "nothing settling, nothing to look at again")
        let grown = stamp("b.pdf", size: 11)
        let growing = plan([entry("b.pdf", as: grown)], [], seen: first.seen, at: settled)
        expect(growing.ready.isEmpty && growing.seen["/notes/b.pdf"]?.since == settled,
               "a file whose size changed between looks starts settling again")
        let retry = plan(entries, jobs, seen: first.seen, at: settled, retryFailed: true)
        expect(retry.ready.map(\.path).contains("/notes/failed.pdf") && !retry.ready.map(\.path).contains("/notes/queued.pdf"),
               "Run Distill retries a settled failed file at once, never one already queued")
        let other = [entry("failed.pdf", as: stamp("failed.pdf", size: 11))]
        let renewed = plan(other, jobs, seen: plan(other, jobs, at: now).seen, at: settled)
        expect(renewed.ready == other, "a failed job blocks the file it read, never a newer file under its name")

        let opening = plan(entries, jobs, existing: nil, at: now)
        let found: Set = ["/notes/a.html", "/notes/b.pdf", "/notes/done.pdf", "/notes/talk.MP3"]
        expect(opening.ready.isEmpty && opening.recheck == nil && Set(opening.existing.keys) == found
               && Set(opening.seen.keys) == ["/notes/failed.pdf", "/notes/queued.pdf"],
               "the first look at a folder converts nothing: what is already there is only remembered, "
               + "apart from a file a job of ours already names: \(opening)")
        let arrived = entries + [entry("new.pdf")]
        let noticed = plan(arrived, jobs, seen: opening.seen, existing: opening.existing, at: settled)
        let later = plan(arrived, jobs, seen: noticed.seen, existing: noticed.existing,
                         at: settled.addingTimeInterval(settle), retryFailed: true)
        expect(noticed.ready.isEmpty && later.ready.map(\.path) == ["/notes/failed.pdf", "/notes/new.pdf"]
               && Set(later.existing.keys) == found,
               "files there at the first look stay untouched however long they sit, Run Distill included; "
               + "one that appears later converts: \(later.ready.map(\.path))")
        let edited = plan([entry("b.pdf", as: grown)], [], existing: opening.existing, at: settled)
        expect(edited.ready.isEmpty && edited.seen.isEmpty && Set(edited.existing.keys) == ["/notes/b.pdf"],
               "a file already there stays left alone when it is edited, and a name that is gone is forgotten")
        let back = plan([entry("a.html")], [], existing: edited.existing, at: settled)
        expect(back.existing.isEmpty && back.recheck == settled.addingTimeInterval(settle),
               "a name that left the folder and came back is a new file")
        let renamed = plan([entry("paper.pdf", as: stamp("b.pdf"))], [], existing: opening.existing, at: settled)
        let kept = plan([entry("paper.pdf", as: stamp("b.pdf"))], [], seen: renamed.seen, existing: renamed.existing,
                        at: settled.addingTimeInterval(settle))
        expect(renamed.ready.isEmpty && renamed.seen.isEmpty && renamed.recheck == nil && kept.ready.isEmpty
               && Set(kept.existing.keys) == ["/notes/paper.pdf"],
               "a file already there stays left alone under a new name: \(renamed)")
        expect(DistillDrop.kind(of: "x.HTM") == .html && DistillDrop.kind(of: "x.md") == nil
               && DistillDrop.kind(of: "x.mov") == .media, "kinds follow the extension, any case")

        let folder = URL(filePath: "/notes/", directoryHint: .isDirectory)
        expect(DistillDrop.isDirectlyInside("/notes/./a.pdf", folder)
               && !DistillDrop.isDirectlyInside("/notes/sub/a.pdf", folder)
               && !DistillDrop.isDirectlyInside("/notes-old/a.pdf", folder),
               "only a file directly in the folder belongs to it, never a string prefix")
        var pending = [job("a.pdf", .waiting), job("b.pdf", .held), job("c.pdf", .running), job("d.pdf", .failed)]
        pending.append(DownloadJob(id: "link", kind: "distill", source: "https://example.com", title: "", created: old))
        pending.append(DownloadJob(id: "other", kind: "audio", source: "/notes/e.mp3", title: "", created: old))
        expect(DistillDrop.orphans(pending, kind: "distill", folder: folder).isEmpty, "the same folder keeps its jobs")
        expect(DistillDrop.orphans(pending, kind: "distill", folder: URL(filePath: "/elsewhere/")) == ["a.pdf", "b.pdf", "c.pdf"]
               && DistillDrop.orphans(pending, kind: "distill", folder: nil) == ["a.pdf", "b.pdf", "c.pdf"],
               "a new folder or Convert off cancels every unfinished dropped file, never a link")
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
        let watched = Watched(folder)
        let runner = runner(root, notes: notes, busy: busy, watched: watched)

        let page = folder.appending(path: "page.html")
        try Data("<html><body><h1>Head</h1><p>Body text</p></body></html>".utf8).write(to: page)
        let pageNote = try await runner.run(dropped(page), context: context)
        expect(pageNote == folder.appending(path: "page.md"), "an HTML file becomes a note beside where it was")
        let text = try String(contentsOf: folder.appending(path: "page.md"), encoding: .utf8)
        expect(text.hasPrefix("---\ntitle: \"page\"\nsource: \"page.html\"\nsaved: 2025-11-18\n---\n\n")
               && text.contains("Body text"), "its note names the file it came from: \(text)")
        expect(!FileManager.default.fileExists(atPath: page.path)
               && FileManager.default.fileExists(atPath: bin.appending(path: "page.html").path),
               "the converted original goes to the Trash")

        let audio = folder.appending(path: "talk.mp3")
        try Data("audio".utf8).write(to: audio)
        _ = try await runner.run(dropped(audio), context: context)
        try expect(String(contentsOf: folder.appending(path: "talk.md"), encoding: .utf8).hasSuffix("\n\nhello\nhello\n"),
                   "an audio file becomes its transcript")

        let linked = folder.appending(path: "linked.html")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: bin.appending(path: "page.html"))
        await expectFailure(.unsupported, "a symlink is never converted") {
            _ = try await runner.run(dropped(linked), context: context)
        }
        await expectFailure(.noFolder, "a dropped file with no Markdown folder set fails plainly") {
            _ = try await Self.runner(root, notes: nil).run(dropped(audio), context: context)
        }

        let empty = folder.appending(path: "empty.html")
        try Data("<html><body></body></html>".utf8).write(to: empty)
        await expectFailure(.unreadable, "an HTML file with no text fails unreadable") {
            _ = try await runner.run(dropped(empty), context: context)
        }
        expect(FileManager.default.fileExists(atPath: empty.path)
               && !FileManager.default.fileExists(atPath: folder.appending(path: "empty.md").path),
               "an empty file stays in the folder and gets no note")

        let legacy = folder.appending(path: "legacy.html")
        let latin = Data("<html><body><p>Za".utf8) + Data([0xBF, 0xF3, 0xB3, 0xE6]) + Data("</p></body></html>".utf8)
        try latin.write(to: legacy)
        await expectFailure(.unreadable, "an HTML file that is not UTF-8 fails unreadable, never a garbled note") {
            _ = try await runner.run(dropped(legacy), context: context)
        }
        try expect(Data(contentsOf: legacy) == latin
                   && !FileManager.default.fileExists(atPath: folder.appending(path: "legacy.md").path)
                   && !FileManager.default.fileExists(atPath: bin.appending(path: "legacy.html").path),
                   "a file in another encoding stays untouched, out of the Trash, and gets no note")

        let stuck = folder.appending(path: "stuck.html")
        try Data("<p>Stuck</p>".utf8).write(to: stuck)
        var trashless = notes
        trashless.trash = { _ in throw CocoaError(.featureUnsupported) }
        for _ in 0..<2 {
            do {
                _ = try await Self.runner(root, notes: trashless, watched: watched).run(dropped(stuck), context: context)
                preconditionFailure("a file that cannot be trashed fails")
            } catch {
                expect((error as? CocoaError)?.code == .featureUnsupported, "the Trash's own error is the failure: \(error)")
            }
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("stuck") }
        expect(left == ["stuck.html"],
                   "a file that cannot be trashed stays and leaves no note behind, however often it is run")

        try await stayingPut(folder, notes: notes, watched: watched, context: context, root: root)

        let quiet = folder.appending(path: "quiet.mp3")
        try Data("audio".utf8).write(to: quiet)
        let refused = Self.runner(root, notes: notes, busy: busy, watched: watched,
                                  transcribe: { _ in throw NotchcastTranscribeError.busy })
        await expectFailure(.busy, "busy fails the file") { _ = try await refused.run(dropped(quiet), context: context) }
        expect(busy.count == 1 && FileManager.default.fileExists(atPath: quiet.path),
               "busy ends the run and keeps the file for Run Distill")
    }

    /// A queued file is converted and trashed only while Convert is on, in its folder, unchanged since queued.
    private static func stayingPut(
        _ folder: URL, notes: DistillNotes, watched: Watched, context: DownloadRunContext, root: URL
    ) async throws {
        let report = folder.appending(path: "report.html")
        try Data("<p>Report</p>".utf8).write(to: report)
        let job = dropped(report)
        let elsewhere: [(URL?, String)] = [(folder.deletingLastPathComponent(), "the folder changed"), (nil, "Convert is off")]
        for (target, reason) in elsewhere {
            watched.folder = target
            await expectCancelled("\(reason) before the run: nothing converts") {
                _ = try await runner(root, notes: notes, watched: watched).run(job, context: context)
            }
            expect(FileManager.default.fileExists(atPath: report.path)
                   && !FileManager.default.fileExists(atPath: folder.appending(path: "report.md").path),
                   "\(reason): the file stays and gets no note")
        }
        watched.folder = folder

        let talk = folder.appending(path: "moved.mp3")
        try Data("audio".utf8).write(to: talk)
        let switching = runner(root, notes: notes, watched: watched, transcribe: { _ in
            watched.folder = nil
            return "hello"
        })
        await expectCancelled("Convert going off mid-run stops the trash") {
            _ = try await switching.run(dropped(talk), context: context)
        }
        expect(FileManager.default.fileExists(atPath: talk.path), "a file whose folder changed mid-run stays")
        watched.folder = folder

        let replaced = folder.appending(path: "replaced.mp3")
        try Data("audio".utf8).write(to: replaced)
        let replacing = runner(root, notes: notes, watched: watched, transcribe: { _ in
            try Data("a newer, longer recording".utf8).write(to: replaced)
            return "hello"
        })
        await expectFailure(.changed, "a file replaced during transcription is not trashed") {
            _ = try await replacing.run(dropped(replaced), context: context)
        }
        try expect(String(contentsOf: replaced, encoding: .utf8) == "a newer, longer recording",
                   "the newer file stays where it is")
    }

    private static func runner(
        _ root: URL, notes: DistillNotes?, busy: Counter = Counter(), watched: Watched? = nil,
        transcribe: @escaping DistillRunner.Transcribe = { _ in "hello" }
    ) -> DistillRunner {
        DistillRunner(workDirectory: root.appending(path: "work", directoryHint: .isDirectory), transcribe: transcribe,
                      timestamps: { false }, onBusy: { busy.count += 1 }, notes: { notes },
                      dropFolder: { if let watched { watched.folder } else { notes?.folder } })
    }

    /// A dropped file's job as the watcher queues it: its path and the stamp it had when it settled.
    private static func dropped(_ file: URL) -> DownloadJob {
        var job = Self.job(file.path(percentEncoded: false))
        job.encodedOptions = DistillDrop.stamp(at: job.source).flatMap { try? DownloadJob.encode($0) }
        return job
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

    private static func expectCancelled(_ message: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            preconditionFailure(message + ": it succeeded")
        } catch {
            expect(error is CancellationError, message + ": \(error)")
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

/// The folder Convert dropped files watches as the runner reads it; nil is Convert off.
@MainActor
private final class Watched {
    var folder: URL?

    init(_ folder: URL?) { self.folder = folder }
}

/// Stands in for yt-dlp and ffmpeg: metadata, one audio file, then two chunks.
private struct FakeTools: DownloadToolHost {
    func capture(_ executable: URL, arguments: [String], limit: Int) async throws -> (status: Int32, data: Data) {
        throw POSIXError(.ENOSYS)
    }

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
