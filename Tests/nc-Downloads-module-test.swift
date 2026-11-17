// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/CaptionText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsIslandPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsLinks.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLMarkdown.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaArguments.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaFailure.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageArticle.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageExtraction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
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
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit

/// Pins the v1 switch ids, the five commands, the queue following its switch, and a stop keeping accepted links.
@main
@MainActor
struct DownloadsModuleTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-module-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        shape()
        try await lifecycle(root)
        print("Downloads module: v1 switches, five commands, queue follows its switch, stop keeps accepted links")
    }

    private static func shape() {
        let switches = DownloadsAddon.switches
        expect(switches.map(\.id) == ["downloads", "downloadsAria2"], "v1 raw ids stay")
        expect(switches.allSatisfy { !$0.defaultEnabled && $0.category == .filesDownloads && $0.requiredGrants.isEmpty },
               "every switch starts off in Files & Downloads")
        expect(switches.map(\.dependencies) == [[], ["downloads"]], "aria2 needs Downloads")
        expect(DownloadsAddon.commands.map(\.slug) == [
            "download-video", "download-audio", "download-youtube-transcript", "save-webpage-as-markdown",
            "open-downloads-folder",
        ], "command slugs")
        expect(DownloadsAddon.commands.allSatisfy { $0.switchID == "downloads" }, "every command follows Downloads")
    }

    private static func lifecycle(_ root: URL) async throws {
        let suite = "nc-downloads-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fakes = Fakes()
        let downloads = root.appending(path: "home/Downloads", directoryHint: .isDirectory)
        let queues = root.appending(path: "queues", directoryHint: .isDirectory)
        let environment = DownloadsModule.Environment(
            downloads: downloads, queues: queues,
            tools: DownloadToolLookup(directories: [root.appending(path: "bin")], home: root),
            clipboard: { fakes.clipboard }, openFolder: { fakes.opened.append($0) })
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let preferences = NotchcastPreferences(defaults: defaults, switches: DownloadsAddon.switches)
        let presenter = RecordingPresenter()
        let context = NotchcastContext(defaults: defaults, preferences: preferences, presenter: presenter, hub: hub,

                                       transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
                                       now: { .now }, onTapsChanged: {})
        let module = DownloadsModule(context: context, environment: environment)
        context.attach(module)
        func command(_ slug: String) { DownloadsAddon.commands.first { $0.slug == slug }!.run(context) }

        module.start()
        expect(module.downloads.queue == nil, "switch off: no queue runs")
        command("download-video")
        command("open-downloads-folder")
        expect(presenter.log.isEmpty && fakes.opened.isEmpty, "switch off: commands do nothing")

        preferences.set("downloads", on: true)
        try await eventually { module.downloads.queue != nil }
        expect(module.downloads.destination == downloads, "downloads land in ~/Downloads")
        fakes.clipboard = "no links here"
        command("download-video")
        expect(presenter.log.last == "post downloads.noLinks No Web Links in Clipboard", "no links is reported")
        command("open-downloads-folder")
        expect(fakes.opened == [downloads], "open Downloads opens ~/Downloads")

        preferences.set("downloads", on: false)
        try await eventually { module.downloads.queue == nil }
        preferences.set("downloads", on: true)
        try await eventually { module.downloads.queue != nil }

        fakes.clipboard = "https://example.com/clip"
        command("download-video")
        expect(module.downloads.queue?.jobs.map(\.source) == ["https://example.com/clip"],
               "a copied link joins the running queue at once")
        module.stop()
        let saved = try JSONDecoder().decode(
            [DownloadJob].self, from: Data(contentsOf: queues.appending(path: "downloads.json")))
        expect(saved.map(\.source) == ["https://example.com/clip"],
               "quit: a link accepted just before stop is already on disk when stop returns")
        expect(module.downloads.queue == nil, "stop ends the queue")
        module.stop()
        expect(module.downloads.queue == nil, "a second stop is a no-op")

        module.start()
        fakes.clipboard = "https://example.com/early"
        command("download-video")
        module.stop()
        expect(presenter.log.last == "post downloads.starting Downloads is starting. Try again.",
               "a command while the queue loads is turned away out loud, never dropped silently")

        module.start()
        try await eventually { module.downloads.queue != nil }
        try FileManager.default.removeItem(at: queues)
        try Data("blocked".utf8).write(to: queues)
        let posted = presenter.log.count
        fakes.clipboard = "https://example.com/unsaved"
        command("download-video")
        module.stop()
        try await Task.sleep(for: .milliseconds(50))
        expect(presenter.log[posted...].contains { $0.hasPrefix("post downloads.error ") },
               "a link that could not be saved is reported even when stop follows at once")
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
    }
}

extension DownloadsModule.Environment {
    /// The app's real environment is never built here: the addon's makeModule is not called.
    static func live() -> Self { fatalError("the harness builds its own environment") }
}
