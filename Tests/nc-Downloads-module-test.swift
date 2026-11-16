// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/CaptionText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillAudioChunks.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillTranscript.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsFolders.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsIslandPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsLinks.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLMarkdown.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/LinkCleaner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaArguments.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaFailure.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageArticle.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageExtraction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/YtDlpAudio.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillTranscriber.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsIslandBridge.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/MediaDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebAddress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebProxy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TranscriptDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
import AppKit

/// Pins the v1 switch ids, the eight commands, each queue following its own switch, and stop releasing speech.
@main
@MainActor
struct DownloadsModuleTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-module-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        shape()
        try await lifecycle(root)
        print("Downloads module: v1 switches, eight commands, queues follow their switches, timestamps follow F63")
    }

    private static func shape() {
        let switches = DownloadsAddon.switches
        expect(switches.map(\.id) == ["downloads", "downloadsAria2", "distill", "distillTimestamps"], "v1 raw ids stay")
        expect(switches.allSatisfy { !$0.defaultEnabled && $0.category == .filesDownloads && $0.requiredGrants.isEmpty },
               "every switch starts off in Files & Downloads")
        expect(switches.map(\.dependencies) == [[], ["downloads"], [], ["distill"]], "options need their feature")
        expect(DownloadsAddon.commands.map(\.slug) == [
            "download-video", "download-audio", "download-youtube-transcript", "save-webpage-as-markdown",
            "open-downloads-folder", "add-links-to-distill", "run-distill", "open-distill-folder",
        ], "command slugs")
        expect(DownloadsAddon.commands.map(\.switchID) == Array(repeating: "downloads", count: 5)
               + Array(repeating: "distill", count: 3), "each command follows its feature switch")
    }

    private static func lifecycle(_ root: URL) async throws {
        let suite = "nc-downloads-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bin = root.appending(path: "bin")
        try tools(in: bin)
        let fakes = Fakes()
        let folders = DownloadsFolders(home: root.appending(path: "home"))
        let environment = DownloadsModule.Environment(
            downloads: folders.downloads, distill: folders.distill, queues: root.appending(path: "queues"),
            work: root.appending(path: "work"), tools: DownloadToolLookup(directories: [bin], home: root),
            clipboard: { fakes.clipboard }, openFolder: { fakes.opened.append($0) },
            recognize: { _ in "Spoken words." }, releaseSpeech: {}, stopSpeech: { fakes.speechStops += 1 },
            saveWebpage: { source, destination in
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let file = destination.appending(path: "page.md")
                try Data("# \(source.absoluteString)\n".utf8).write(to: file)
                return file
            })
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let preferences = NotchcastPreferences(defaults: defaults, switches: DownloadsAddon.switches)
        let presenter = RecordingPresenter()
        let context = NotchcastContext(defaults: defaults, preferences: preferences, presenter: presenter, hub: hub,
                                       now: { .now }, onTapsChanged: {})
        let module = DownloadsModule(context: context, environment: environment)
        context.attach(module)
        func command(_ slug: String) { DownloadsAddon.commands.first { $0.slug == slug }!.run(context) }

        module.start()
        await settle(module)
        expect(module.downloads.queue == nil && module.distill.queue == nil, "switches off: no queue runs")
        command("download-video")
        command("open-distill-folder")
        expect(presenter.log.isEmpty && fakes.opened.isEmpty, "switches off: commands do nothing")

        preferences.set("downloads", on: true)
        try await eventually { module.downloads.queue != nil }
        expect(module.distill.queue == nil, "Downloads on leaves Distill stopped")
        expect(module.downloads.destination == folders.downloads, "downloads land in ~/Downloads")
        fakes.clipboard = "no links here"
        command("download-video")
        expect(presenter.log.last == "post downloads.noLinks No Web Links in Clipboard", "no links is reported")
        command("open-downloads-folder")
        expect(fakes.opened == [folders.downloads], "open Downloads opens ~/Downloads")

        preferences.set("distill", on: true)
        try await eventually { module.distill.queue != nil }
        expect(module.distill.destination == folders.distill, "Distill paths: the Distill queue writes to Distill/Raw")
        command("open-distill-folder")
        expect(fakes.opened.last == folders.distill, "Distill paths: open Distill opens Distill/Raw")
        let distill = module.distill.queue!

        fakes.clipboard = "https://example.com/a https://youtu.be/abc"
        command("add-links-to-distill")
        command("add-links-to-distill")
        try await eventually { distill.jobs.count == 2 }
        expect(distill.jobs.allSatisfy { $0.state == .held }, "added links wait for Run Distill")
        try await Task.sleep(for: .milliseconds(50))
        expect(distill.jobs.count == 2, "a link already held is not added twice")
        command("run-distill")
        try await eventually { distill.jobs.allSatisfy(\.state.isFinished) }
        expect(distill.jobs.allSatisfy { $0.state == .done }, "both distill jobs finish: \(distill.jobs.map(\.detail))")
        let outputs = distill.jobs.compactMap(\.output).map { URL(filePath: $0) }
        expect(outputs.count == 2 && outputs.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.path == folders.distill.standardizedFileURL.path
        }, "Distill paths: page and transcript land in Distill/Raw: \(outputs)")
        let plain = try String(contentsOf: outputs.first { $0.pathExtension == "txt" }!, encoding: .utf8)
        expect(plain == "Spoken words.\n", "timestamps: off by default")
        try await eventually { presenter.log.contains("end distill.progress") }
        expect(presenter.log.contains { $0.hasPrefix("post distill.progress") }, "Distill progress reaches the island")

        preferences.set("distillTimestamps", on: true)
        fakes.clipboard = "https://youtu.be/def"
        command("add-links-to-distill")
        command("run-distill")
        try await eventually { distill.jobs.count == 3 && distill.jobs.allSatisfy(\.state.isFinished) }
        let timed = distill.jobs.first { $0.source.contains("def") }!.output.map { URL(filePath: $0) }!
        try expect(String(contentsOf: timed, encoding: .utf8) == "[00:00:00] Spoken words.\n",
               "timestamps: F63 on adds the clock")

        preferences.set("distill", on: false)
        try await eventually { module.distill.queue == nil }
        expect(module.downloads.queue != nil, "Distill off leaves Downloads running")
        fakes.clipboard = "https://example.com/b"
        command("add-links-to-distill")
        expect(presenter.log.last != "post downloads.noLinks No Web Links in Clipboard" && module.distill.queue == nil,
               "Distill off: its commands do nothing")
        expect(fakes.speechStops == 0, "a switch going off keeps the module's speech worker")

        module.stop()
        await settle(module)
        expect(module.downloads.queue == nil && module.distill.queue == nil, "stop ends every queue")
        expect(fakes.speechStops == 1, "stop ends the speech worker")
        module.stop()
        expect(fakes.speechStops == 1, "a second stop is a no-op")
        expect(FileManager.default.fileExists(atPath: root.appending(path: "queues/distill.json").path),
               "the Distill queue persists for the next launch")
    }

    private static func settle(_ module: DownloadsModule) async {
        await module.downloads.settle()
        await module.distill.settle()
    }

    /// yt-dlp prints metadata or writes the audio file; ffmpeg writes one second of silent PCM.
    private static func tools(in bin: URL) throws {
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
        #!/usr/bin/python3
        import sys, json
        a = sys.argv
        if '--print' in a:
            print(json.dumps({'title': 'Title', 'channel': 'Channel', 'id': a[-1][-3:]}))
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
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }

    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum HarnessError: Error { case timeout }

    @MainActor private final class Fakes {
        var clipboard = ""
        var opened: [URL] = []
        var speechStops = 0
    }
}

extension DownloadsModule.Environment {
    /// The app's real environment is never built here: the addon's makeModule is not called.
    static func live() -> Self { fatalError("the harness builds its own environment") }
}
