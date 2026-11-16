import Foundation
import Observation

/// Owns the downloads queue, which runs while the Downloads switch is on.
@MainActor
final class DownloadsModule: NotchcastModule {
    enum Action: CaseIterable {
        case video, audio, transcript, webpage, openDownloads

        /// The job kind a copied link becomes; nil for the command that only opens the folder.
        var kind: String? {
            switch self {
            case .video: MediaArguments.Format.video.kind
            case .audio: MediaArguments.Format.audio.kind
            case .transcript: TranscriptDownloadRunner.kind
            case .webpage: WebpageRunner.kind
            case .openDownloads: nil
            }
        }
    }

    /// Everything the module takes from the Mac; the harnesses hand in scratch folders and fakes.
    struct Environment {
        var downloads: URL
        var queues: URL
        var tools: DownloadToolLookup
        var clipboard: @MainActor () -> String
        var openFolder: @MainActor (URL) throws -> Void
    }

    static let switchID = "downloads"
    let downloads: DownloadsQueueController
    private let context: NotchcastContext
    private let environment: Environment
    private var running = false
    private var active = false

    init(context: NotchcastContext, environment: Environment) {
        self.context = context
        self.environment = environment
        downloads = DownloadsQueueController(
            file: environment.queues.appending(path: "downloads.json"), destination: environment.downloads,
            tools: environment.tools,
            report: { [presenter = context.presenter] message in
                presenter.post(IslandNotice(id: "downloads.error", symbol: "exclamationmark.triangle", text: message,
                                            isFailure: true, seconds: 5), onTap: nil)
            })
        DownloadsIslandBridge.track(downloads, presenter: context.presenter, noticeID: "downloads.progress",
                                    symbol: "arrow.down.circle")
    }

    func start() {
        guard !running else { return }
        running = true
        follow()
    }

    func stop() {
        guard running else { return }
        running = false
        if active { downloads.stop() }
        active = false
    }

    func perform(_ action: Action) {
        guard running, context.isEnabled(Self.switchID) else { return }
        guard let kind = action.kind else { return open(downloads.destination) }
        let links = DownloadsLinks.urls(in: environment.clipboard())
        if links.isEmpty {
            return context.presenter.post(IslandNotice(
                id: "downloads.noLinks", symbol: "link",
                text: String(localized: "No Web Links in Clipboard", table: "NotchcastDownloads"), isFailure: true),
                onTap: nil)
        }
        guard !downloads.accept(kind: kind, sources: links) else { return }
        context.presenter.post(IslandNotice(
            id: "downloads.starting", symbol: "arrow.down.circle",
            text: String(localized: "Downloads is starting. Try again.", table: "NotchcastDownloads"),
            isFailure: true), onTap: nil)
    }

    private func open(_ folder: URL) {
        do {
            try environment.openFolder(folder)
        } catch {
            context.presenter.post(IslandNotice(id: "downloads.error", symbol: "folder",
                                                text: error.localizedDescription, isFailure: true), onTap: nil)
        }
    }

    /// Starts or stops the queue as the switch goes on or off while the module runs.
    private func follow() {
        guard running else { return }
        let enabled = withObservationTracking { context.isEnabled(Self.switchID) } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.follow() }
        }
        if enabled != active {
            if enabled { downloads.start(configure: configure) } else { downloads.stop() }
        }
        active = enabled
    }

    private func configure(_ queue: DownloadQueue) {
        let preferences = context.preferences
        for format in [MediaArguments.Format.video, .audio] {
            queue.register(MediaDownloadRunner(format: format, aria2Enabled: {
                preferences.isEnabled("downloadsAria2")
            }))
        }
        queue.register(TranscriptDownloadRunner())
        queue.register(WebpageRunner())
    }
}
