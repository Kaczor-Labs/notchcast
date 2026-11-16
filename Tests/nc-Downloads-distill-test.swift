// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillAudioChunks.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillTranscript.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsFolders.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/LinkCleaner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/YtDlpAudio.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillTranscriber.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift
import Foundation
import Synchronization

/// Pins Distill: link cleaning, naming, chunking, output under the Distill folder, and timestamps only on request.
@main
@MainActor
struct DownloadsDistillTest {
    @MainActor private final class Recognition {
        var counts = [Int]()
        var answers = ["A first chunk ends.", "New speech follows."]

        func transcribe(_ samples: [Float]) -> String {
            counts.append(samples.count)
            return answers.removeFirst()
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-distill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        links()
        naming()
        chunks()
        folders(root)
        try publication(root)
        try await transcription(root)
        try await busy()
        try await runner(root)
        print("Downloads distill: links, naming, chunks, Distill folder, timestamps only when on, cancellation")
    }

    private static func links() {
        let links = LinkCleaner.links(in: """
        <https://youtu.be/AbC_123-x?si=share> https://www.youtube.com/shorts/AbC_123-x
        https://m.youtube.com/watch?v=AbC_123-x&t=10 https://example.com/article/?utm_source=a#heading
        http://www.example.com/article https://twitter.com/person/status/123?s=20
        https://x.com/person/status/123?t=tracking https://example.com/Essay_(draft).
        """)
        expect(links == ["https://www.youtube.com/watch?v=AbC_123-x", "https://example.com/article",
                         "https://twitter.com/person/status/123", "https://example.com/Essay_(draft)"], "link dedupe")
        expect(LinkCleaner.clean("file:///etc/passwd") == nil, "file link refused")
        expect(LinkCleaner.clean("https://user:secret@example.com/") == nil, "credentialed link refused")
        expect(LinkCleaner.clean("https://youtube.com/watch") == nil, "watch without id refused")
        expect(LinkCleaner.clean("https://youtu.be/a%26b") == nil, "bad id refused")
        expect(LinkCleaner.clean("https://EXAMPLE.com:443/?q=Keep&utm_medium=x") == "https://example.com?q=Keep", "clean")
        expect(LinkCleaner.key("https://example.com/Case") != LinkCleaner.key("https://example.com/case"), "path case kept")
        let arguments = YtDlpAudio.audioArguments(link: "https://example.com/video", folder: URL(filePath: "/test"))
        expect(arguments.contains("--ignore-config") && arguments.contains("--no-playlist"), "audio arguments")
        expect(!arguments.contains("--cookies-from-browser") && arguments.suffix(2).first == "--", "no cookies, link last")
    }

    private static func naming() {
        expect(DistillTranscript.fileName(channel: "Channel", title: "Title") == "Channel - Title.txt", "name")
        let name = DistillTranscript.fileName(channel: "../Channel/Name", title: "Title: with \\ bad<>\"|?*\u{0}characters")
        expect(!name.hasPrefix(".") && !name.contains(where: { "/:\\<>\"|?*\u{0}".contains($0) }), "name sanitized")
        expect(DistillTranscript.fileName(channel: "", title: "...") == "Untitled.txt", "untitled")
        let long = DistillTranscript.fileName(
            channel: String(repeating: "猫", count: 200), title: String(repeating: "🐈", count: 200))
        expect(long.utf8.count <= 207, "name bounded")
        expect(DistillTranscript.clock(3661) == "[01:01:01]" && DistillTranscript.clock(-1) == "[00:00:00]", "clock")
    }

    private static func chunks() {
        expect(DistillAudioChunks.maximumSamples == DictationWire.sampleRate * 240, "chunk limit follows wire rate")
        let chunk = DistillAudioChunks.Chunk(offset: Int64(DictationWire.sampleRate) * 5 / 4, count: 4_000)
        expect(chunk.start == 1.25, "chunk start follows wire rate")
        let maximum = DistillAudioChunks.maximumSamples
        var samples = [Float](repeating: 1, count: maximum)
        let silence = (maximum - 24_000)..<(maximum - 20_800)
        samples.replaceSubrange(silence, with: repeatElement(Float.zero, count: silence.count))
        let cut = DistillAudioChunks.cut(in: samples, final: false)
        expect(silence.contains(cut) && cut < DictationWire.maximumSamples, "chunk cuts in silence")
        expect(DistillAudioChunks.cut(in: samples, final: true) == maximum, "final chunk keeps everything")
    }

    private static func folders(_ root: URL) {
        let folders = DownloadsFolders(home: root)
        expect(folders.downloads.standardizedFileURL.path == root.appending(path: "Downloads").standardizedFileURL.path,
               "Distill paths: downloads land in ~/Downloads")
        expect(folders.distill.standardizedFileURL.path
               == root.appending(path: "Downloads/Distill/Raw").standardizedFileURL.path,
               "Distill paths: transcripts land in ~/Downloads/Distill/Raw")
    }

    private static func publication(_ root: URL) throws {
        let folder = root.appending(path: "Raw")
        let first = try DistillRunner.save("first\n", name: "Channel - Title.txt", in: folder)
        let second = try DistillRunner.save("second\n", name: "Channel - Title.txt", in: folder)
        expect(second.lastPathComponent == "Channel - Title (2).txt", "second publication gets a suffix")
        try expect(String(contentsOf: first, encoding: .utf8) == "first\n", "first text")
        try expect(String(contentsOf: second, encoding: .utf8) == "second\n", "second text")
        do {
            _ = try DistillRunner.save("", name: "Empty.txt", in: folder)
            preconditionFailure("empty transcript published")
        } catch {}
        do {
            _ = try DistillRunner.save("x", name: "../Escape.txt", in: folder)
            preconditionFailure("a path name escaped the folder")
        } catch {}
        try expect(FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2, "only two files published")
    }

    private static func transcription(_ root: URL) async throws {
        let pcm = root.appending(path: "fixture.f32")
        expect(FileManager.default.createFile(atPath: pcm.path, contents: nil), "pcm fixture")
        let handle = try FileHandle(forWritingTo: pcm)
        let count = DistillAudioChunks.maximumSamples + 16_000
        try handle.truncate(atOffset: UInt64(count * 4))
        try handle.close()
        let recognition = Recognition()
        let transcriber = DistillTranscriber { recognition.transcribe($0) }
        let progress = Mutex<[Int]>([])
        let result = try await transcriber.transcribePCM(file: pcm) { completed, _ in
            progress.withLock { $0.append(completed) }
        }
        expect(recognition.counts == [DistillAudioChunks.maximumSamples - 1_600, 17_600], "chunk sizes")
        expect(recognition.counts.reduce(0, +) == count, "every sample recognized once")
        expect(result.count == 2 && result[1].start == 239.9 && result[1].text == "New speech follows.", "segments")
        expect(DistillTranscript.text(result, times: true).contains("[00:03:59] New speech follows."),
               "timestamps: shown when asked")
        expect(!DistillTranscript.text(result, times: false).contains("[00:"), "timestamps: absent when not asked")
        expect(progress.withLock { $0 } == [1, 2], "progress per chunk")
        let cancelled = Task { try await transcriber.transcribePCM(file: pcm) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("cancelled transcription succeeded")
        } catch is CancellationError {}
        expect(recognition.counts.count == 2, "cancelled transcription recognized nothing")
        try Data([0, 1, 2]).write(to: pcm)
        do {
            _ = try await transcriber.transcribePCM(file: pcm)
            preconditionFailure("corrupt PCM accepted")
        } catch is CocoaError {}
    }

    private static func busy() async throws {
        var attempts = 0
        let retrying = DistillTranscriber { _ in
            attempts += 1
            if attempts <= 3 { throw DictationWire.Failure.busy }
            return "Ready"
        }
        let text = try await retrying.recognizeWhenAvailable([0])
        expect(text == "Ready" && attempts == 4, "busy recognizer retried")
        let ready = AsyncStream<Void>.makeStream()
        let blocked = DistillTranscriber { _ in
            ready.continuation.yield(())
            throw DictationWire.Failure.busy
        }
        let task = Task { try await blocked.recognizeWhenAvailable([0]) }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("busy retry ignored cancellation")
        } catch is CancellationError {}
        let stuck = DistillTranscriber(recognize: { _ in throw DictationWire.Failure.busy }, busyLimit: .milliseconds(300))
        do {
            _ = try await stuck.recognizeWhenAvailable([0])
            preconditionFailure("busy wait was unbounded")
        } catch DictationWire.Failure.busy {}
        let failed = DistillTranscriber { _ in throw DictationWire.Failure.notInstalled }
        do {
            _ = try await failed.recognizeWhenAvailable([0])
            preconditionFailure("non-busy error retried")
        } catch DictationWire.Failure.notInstalled {}
    }

    private static func runner(_ root: URL) async throws {
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
        #!/usr/bin/python3
        import sys, json
        a = sys.argv
        if '--print' in a:
            print(json.dumps({'title': 'Title', 'channel': 'Channel'}))
            print(json.dumps({'title': 'Second entry'}))
        elif '-o' in a:
            open(a[a.index('-o') + 1].replace('%(ext)s', 'm4a'), 'wb').write(b'0')
        else:
            open(a[-1], 'wb').write(bytes(64000))
        """
        for tool in ["yt-dlp", "ffmpeg"] {
            let file = bin.appending(path: tool)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let distill = DownloadsFolders(home: root).distill
        let stages = Mutex<[String]>([])
        let context = DownloadRunContext(
            destination: distill, tools: DownloadToolLookup(directories: [bin], home: root),
            report: { value in stages.withLock { $0.append(value.stage ?? "") } })
        let work = root.appending(path: "runner-work")
        let pages = Mutex<[URL]>([])
        let saveWebpage: DistillRunner.SaveWebpage = { _, target in
            pages.withLock { $0.append(target) }
            return target.appending(path: "webpage.md")
        }
        let timestamps = Toggle()
        let runner = DistillRunner(transcriber: DistillTranscriber { _ in "A transcript." }, workDirectory: work,
                                   timestamps: { timestamps.on }, saveWebpage: saveWebpage)
        let registered: any DownloadRunner = runner
        expect(registered.kind == "distill" && registered.tools.isEmpty, "a web link needs no tool")
        let plain = try await registered.run(job("https://youtu.be/abc"), context: context)!
        try expect(String(contentsOf: plain, encoding: .utf8) == "A transcript.\n",
                   "timestamps: off writes plain lines")
        expect(plain.deletingLastPathComponent().standardizedFileURL.path == distill.standardizedFileURL.path,
               "Distill paths: a transcript lands in the Distill folder")
        expect(plain.lastPathComponent == "Channel - Title.txt", "transcript named after channel and title")
        expect(stages.withLock { $0 } == ["Transcribing 1 of 1"], "transcription progress")
        timestamps.on = true
        let timed = try await registered.run(job("https://youtu.be/def"), context: context)!
        try expect(String(contentsOf: timed, encoding: .utf8) == "[00:00:00] A transcript.\n",
                   "timestamps: on writes a clock per line")
        try expect(FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty, "work folder emptied")
        let page = try await registered.run(job("https://open.spotify.com/track/fixture"), context: context)!
        expect(page.lastPathComponent == "webpage.md" && pages.withLock { $0 } == [distill],
               "Distill paths: a web link is saved into the Distill folder")
        let fileText = try await runner.transcriber.text(file: plain, workDirectory: work, context: context)
        expect(fileText == "A transcript.\n", "a transcript fallback never carries timestamps")

        let ready = AsyncStream<Void>.makeStream()
        let slow = DistillRunner(transcriber: DistillTranscriber { _ in
            ready.continuation.yield(())
            try await Task.sleep(for: .seconds(60))
            return "Late text"
        }, workDirectory: work, timestamps: { false }, saveWebpage: saveWebpage)
        let cancelledOutput = root.appending(path: "cancelled-output")
        let cancelled = Task {
            try await slow.run(source: "https://youtu.be/cancelled", destination: cancelledOutput, context: context)
        }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("cancelled runner published a transcript")
        } catch is CancellationError {}
        expect(!FileManager.default.fileExists(atPath: cancelledOutput.path), "cancelled run publishes nothing")
        try expect(FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty, "cancelled run cleans up")
    }

    private static func job(_ source: String) -> DownloadJob {
        DownloadJob(id: UUID().uuidString, kind: "distill", source: source, title: "Fixture", created: .distantPast)
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }

    @MainActor private final class Toggle {
        var on = false
    }
}
