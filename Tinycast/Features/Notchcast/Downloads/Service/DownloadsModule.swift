import Foundation
import Observation

/// Owns the downloads and Distill queues; each runs while its own switch is on.
@MainActor
final class DownloadsModule: NotchcastModule {
    enum Action: CaseIterable {
        case video, audio, transcript, webpage, openDownloads, addDistill, runDistill, openDistill

        /// The job kind a copied link becomes in the downloads queue; nil for every other command.
        var kind: String? {
            switch self {
            case .video: MediaArguments.Format.video.kind
            case .audio: MediaArguments.Format.audio.kind
            case .transcript: TranscriptDownloadRunner.kind
            case .webpage: WebpageRunner.kind
            case .openDownloads, .addDistill, .runDistill, .openDistill: nil
            }
        }

        var switchID: String {
            switch self {
            case .addDistill, .runDistill, .openDistill: DownloadsModule.distillSwitchID
            default: DownloadsModule.switchID
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
        /// Scratch audio for Distill; each run removes its own folder when it ends.
        var work = FileManager.default.temporaryDirectory.appending(path: "Notchcast Distill", directoryHint: .isDirectory)

        var distill: URL { downloads.appending(path: "Distill/Raw", directoryHint: .isDirectory) }
    }

    nonisolated static let switchID = "downloads"
    nonisolated static let distillSwitchID = "distill"
    let downloads: DownloadsQueueController
    let distill: DownloadsQueueController
    private let context: NotchcastContext
    private let environment: Environment
    private var running = false
    private var active = (downloads: false, distill: false)

    init(context: NotchcastContext, environment: Environment) {
        self.context = context
        self.environment = environment
        let report: (String) -> Void = { [presenter = context.presenter] message in
            presenter.post(IslandNotice(id: "downloads.error", symbol: "exclamationmark.triangle", text: message,
                                        isFailure: true), onTap: nil)
        }
        downloads = DownloadsQueueController(
            file: environment.queues.appending(path: "downloads.json"), destination: environment.downloads,
            tools: environment.tools, report: report)
        distill = DownloadsQueueController(
            file: environment.queues.appending(path: "distill.json"), destination: environment.distill,
            maxConcurrent: 1, tools: environment.tools, report: report)
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
        if active.downloads { downloads.stop() }
        if active.distill { distill.stop() }
        active = (false, false)
    }

    func perform(_ action: Action) {
        guard running, context.isEnabled(action.switchID) else { return }
        switch action {
        case .openDownloads: return open(downloads.destination)
        case .openDistill: return open(distill.destination)
        case .runDistill: return runDistill()
        default: break
        }
        let links = DownloadsLinks.urls(in: environment.clipboard())
        if links.isEmpty {
            return context.presenter.post(IslandNotice(
                id: "downloads.noLinks", symbol: "link",
                text: String(localized: "No Web Links in Clipboard", table: "NotchcastDownloads"), isFailure: true),
                onTap: nil)
        }
        if action == .addDistill { return addDistill(links) }
        guard let kind = action.kind, !downloads.accept(kind: kind, sources: links) else { return }
        post("downloads.starting", "arrow.down.circle",
             String(localized: "Downloads is starting. Try again.", table: "NotchcastDownloads"), isFailure: true)
    }

    /// Holds new links until Run Distill; a link already held, waiting or running is not added twice.
    private func addDistill(_ links: [String]) {
        let pending = Set(distill.queue?.jobs.filter { !$0.state.isFinished }.map(\.source) ?? [])
        let fresh = links.filter { !pending.contains($0) }
        guard distill.accept(kind: DistillRunner.kind, sources: fresh, held: true) else { return distillStarting() }
        let held = distill.queue?.jobs.count { $0.state == .held } ?? 0
        post("distill.added", "text.badge.plus", fresh.isEmpty
            ? String(localized: "Already in Distill", table: "NotchcastDownloads")
            : String(localized: "Waiting for Distill: \(held)", table: "NotchcastDownloads"), isFailure: false)
    }

    private func runDistill() {
        guard let queue = distill.queue else { return distillStarting() }
        guard queue.jobs.contains(where: { $0.state == .held }) else {
            return post("distill.empty", "text.badge.plus",
                        String(localized: "No Links Waiting for Distill", table: "NotchcastDownloads"), isFailure: true)
        }
        queue.release(DistillRunner.kind)
    }

    private func distillStarting() {
        post("distill.starting", "text.badge.plus",
             String(localized: "Distill is starting. Try again.", table: "NotchcastDownloads"), isFailure: true)
    }

    private func post(_ id: String, _ symbol: String, _ text: String, isFailure: Bool) {
        context.presenter.post(IslandNotice(id: id, symbol: symbol, text: text, isFailure: isFailure), onTap: nil)
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
            (downloads: context.isEnabled(Self.switchID), distill: context.isEnabled(Self.distillSwitchID))
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.follow() }
        }
        if enabled.downloads != active.downloads {
            if enabled.downloads { downloads.start(configure: configure) } else { downloads.stop() }
        }
        if enabled.distill != active.distill {
            if enabled.distill { distill.start(configure: configureDistill) } else { distill.stop() }
        }
        active = enabled
    }

    private func configureDistill(_ queue: DownloadQueue) {
        let preferences = context.preferences
        queue.register(DistillRunner(
            workDirectory: environment.work,
            transcribe: { [context] in try await context.transcribe($0) },
            timestamps: { preferences.isEnabled("distillTimestamps") },
            onBusy: { [weak queue] in queue?.hold(DistillRunner.kind) }))
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
