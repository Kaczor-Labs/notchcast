import Foundation
import Observation

/// Owns both queues; each runs while its own switch is enabled, so one can stop without the other.
@MainActor
final class DownloadsModule: NotchcastModule {
    enum Action: CaseIterable {
        case video, audio, transcript, webpage, openDownloads, addDistill, runDistill, openDistill

        var switchID: String { isDistill ? "distill" : "downloads" }
        var isDistill: Bool { [.addDistill, .runDistill, .openDistill].contains(self) }
        var readsLinks: Bool { [.video, .audio, .transcript, .webpage, .addDistill].contains(self) }
    }

    /// Everything the module takes from the Mac; the harnesses hand in scratch folders and fakes.
    struct Environment {
        var downloads: URL
        var distill: URL
        var queues: URL
        var work: URL
        var tools: DownloadToolLookup
        var clipboard: @MainActor () -> String
        var openFolder: @MainActor (URL) throws -> Void
        var recognize: DistillTranscriber.Recognize
        var releaseSpeech: @MainActor @Sendable () async -> Void
        var stopSpeech: @MainActor () -> Void
        var saveWebpage: DistillRunner.SaveWebpage = { source, destination in
            try await WebpageSaver(destination: destination).save(source)
        }
    }

    let downloads: DownloadsQueueController
    let distill: DownloadsQueueController
    private let context: NotchcastContext
    private let environment: Environment
    private var running = false
    private var active = (downloads: false, distill: false)
    private var runTask: Task<Void, Never>?

    init(context: NotchcastContext, environment: Environment) {
        self.context = context
        self.environment = environment
        let report: (String) -> Void = { [presenter = context.presenter] message in
            presenter.post(IslandNotice(id: "downloads.error", symbol: "exclamationmark.triangle", text: message,
                                        isFailure: true, seconds: 5), onTap: nil)
        }
        downloads = DownloadsQueueController(
            file: environment.queues.appending(path: "downloads.json"), destination: environment.downloads,
            speechKinds: [TranscriptDownloadRunner.kind], tools: environment.tools,
            releaseSpeech: environment.releaseSpeech, report: report)
        distill = DownloadsQueueController(
            file: environment.queues.appending(path: "distill.json"), destination: environment.distill,
            maxConcurrent: 1, speechKinds: [DistillRunner.kind], tools: environment.tools,
            releaseSpeech: environment.releaseSpeech, report: report)
        DownloadsIslandBridge.track(downloads, presenter: context.presenter, noticeID: "downloads.progress",
                                    symbol: "arrow.down.circle")
        DownloadsIslandBridge.track(distill, presenter: context.presenter, noticeID: "distill.progress",
                                    symbol: "text.badge.plus")
    }

    func start() {
        guard !running else { return }
        running = true
        follow()
    }

    func stop() {
        guard running else { return }
        running = false
        runTask?.cancel()
        runTask = nil
        if active.downloads { downloads.stop() }
        if active.distill { distill.stop() }
        active = (false, false)
        environment.stopSpeech()
    }

    func perform(_ action: Action) {
        guard running, context.isEnabled(action.switchID) else { return }
        let controller = action.isDistill ? distill : downloads
        if action == .openDownloads || action == .openDistill { return open(controller.destination) }
        let links = action.readsLinks ? DownloadsLinks.urls(in: environment.clipboard()) : []
        if action.readsLinks, links.isEmpty {
            return context.presenter.post(IslandNotice(
                id: "downloads.noLinks", symbol: "link",
                text: String(localized: "No Web Links in Clipboard", table: "NotchcastDownloads"), isFailure: true),
                onTap: nil)
        }
        let task = Task { [weak self] in
            await controller.settle()
            guard let self, running, !Task.isCancelled, context.isEnabled(action.switchID),
                  let queue = controller.queue else { return }
            apply(action, links: links, to: queue)
        }
        if action == .runDistill {
            runTask?.cancel()
            runTask = task
        }
    }

    private func apply(_ action: Action, links: [String], to queue: DownloadQueue) {
        switch action {
        case .video: queue.enqueue(kind: MediaArguments.Format.video.kind, sources: links)
        case .audio: queue.enqueue(kind: MediaArguments.Format.audio.kind, sources: links)
        case .transcript: queue.enqueue(kind: TranscriptDownloadRunner.kind, sources: links)
        case .webpage: queue.enqueue(kind: WebpageRunner.kind, sources: links)
        case .addDistill:
            // A link already held, waiting or running is not added a second time.
            var keys = Set(queue.jobs.filter { $0.kind == DistillRunner.kind && !$0.state.isFinished }
                .map { LinkCleaner.key($0.source) })
            let fresh = LinkCleaner.links(in: links.joined(separator: "\n"))
                .filter { keys.insert(LinkCleaner.key($0)).inserted }
            queue.enqueue(kind: DistillRunner.kind, sources: fresh, held: true)
        case .runDistill: queue.release(DistillRunner.kind)
        case .openDownloads, .openDistill: break
        }
    }

    private func open(_ folder: URL) {
        do {
            try environment.openFolder(folder)
        } catch {
            context.presenter.post(IslandNotice(id: "downloads.error", symbol: "folder",
                                                text: error.localizedDescription, isFailure: true), onTap: nil)
        }
    }

    /// Starts or stops each queue as its switch goes on or off while the module runs.
    private func follow() {
        guard running else { return }
        let enabled = withObservationTracking {
            (downloads: context.isEnabled("downloads"), distill: context.isEnabled("distill"))
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.follow() }
        }
        if enabled.downloads != active.downloads {
            if enabled.downloads { downloads.start(configure: configureDownloads) } else { downloads.stop() }
        }
        if enabled.distill != active.distill {
            if enabled.distill { distill.start(configure: configureDistill) } else { distill.stop() }
        }
        active = enabled
    }

    private func configureDownloads(_ queue: DownloadQueue) {
        let preferences = context.preferences
        for format in [MediaArguments.Format.video, .audio] {
            queue.register(MediaDownloadRunner(format: format, aria2Enabled: {
                preferences.isEnabled("downloadsAria2")
            }))
        }
        queue.register(TranscriptDownloadRunner(transcribe: { [transcriber, work = environment.work] job, context in
            try await Self.transcribe(job, context: context, transcriber: transcriber, work: work)
        }))
        queue.register(WebpageRunner())
    }

    private func configureDistill(_ queue: DownloadQueue) {
        let preferences = context.preferences
        queue.register(DistillRunner(
            transcriber: transcriber, workDirectory: environment.work,
            timestamps: { preferences.isEnabled("distillTimestamps") }, saveWebpage: environment.saveWebpage))
    }

    private var transcriber: DistillTranscriber { DistillTranscriber(recognize: environment.recognize) }

    /// The fallback when a video has no captions: its audio, transcribed and saved like a caption file.
    @concurrent
    private static func transcribe(
        _ job: DownloadJob, context: DownloadRunContext, transcriber: DistillTranscriber, work: URL
    ) async throws -> URL {
        guard let cleaned = LinkCleaner.clean(job.source), let url = URL(string: cleaned), YtDlpAudio.isMedia(url)
        else {
            throw MediaFailure(detail: String(
                localized: "Transcript fallback requires a supported media link.", table: "NotchcastDownloads"))
        }
        return try await context.withDistillAudio(link: cleaned, workDirectory: work) { media, audio, folder in
            let text = try await transcriber.text(file: audio, workDirectory: folder, context: context)
            let title = media.id.map { "\(media.title) [\($0)]" } ?? media.title
            return try DistillRunner.save(text, name: DistillTranscript.fileName(channel: nil, title: title),
                                          in: context.destination)
        }
    }
}
