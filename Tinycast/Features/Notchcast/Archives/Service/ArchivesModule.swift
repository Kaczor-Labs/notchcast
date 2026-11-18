import Foundation

/// Extracts opened archives one at a time, journalled so a relaunch resumes the queue.
@MainActor
final class ArchivesModule: NotchcastModule {
    static let switchID = "archives"
    static let defaultAppKey = "archivesDefaultApp"
    static let inPlaceKey = "archivesInPlace"
    private static let noticeID = "archives.extracting"

    private let context: NotchcastContext
    private let environment: ArchivesEnvironment
    private(set) var jobs: [ArchiveJob] = []
    private(set) var current: (job: ArchiveJob, task: Task<Void, Never>)?

    init(context: NotchcastContext, environment: ArchivesEnvironment) {
        self.context = context
        self.environment = environment
    }

    func start() {
        jobs = ArchiveJob.decode((try? Data(contentsOf: environment.journal)) ?? Data())
        environment.routeOpens { [weak self] urls in self?.open(urls) }
        if context.defaults.bool(forKey: Self.defaultAppKey) { environment.setDefaultApp(true) }
        runNext()
    }

    /// A switch turned off gives the archive types back; quitting the app keeps them.
    func stop() {
        environment.routeOpens(nil)
        if !context.isEnabled(Self.switchID), context.defaults.bool(forKey: Self.defaultAppKey) {
            environment.setDefaultApp(false)
        }
        current?.task.cancel()
        current = nil
        context.presenter.end(notice: Self.noticeID)
    }

    func open(_ urls: [URL]) {
        for url in urls {
            guard ArchiveRoute(fileName: url.lastPathComponent) != nil else {
                report(.notArchive(url.lastPathComponent))
                continue
            }
            guard !jobs.contains(where: { $0.archive == url }) else { continue }
            jobs.append(ArchiveJob(id: UUID(), archive: url, inPlace: context.defaults.bool(forKey: Self.inPlaceKey)))
        }
        save()
        runNext()
    }

    func pickAndOpen() { open(environment.pickArchives()) }

    func setDefaultApp(_ on: Bool) { environment.setDefaultApp(on) }

    func cancel(_ id: UUID) {
        if current?.job.id == id {
            current?.task.cancel()
        } else {
            jobs.removeAll { $0.id == id }
            save()
        }
    }

    func cancelAll() {
        let running = current?.job.id
        jobs.removeAll { $0.id != running }
        save()
        if let running { cancel(running) }
    }

    /// Waits for the queue to empty; the harness's only clock.
    func drain() async {
        while let task = current?.task { await task.value }
    }

    private func runNext() {
        guard current == nil, let job = jobs.first else { return }
        let extractor = environment.extractor
        let ask: ArchiveExtractor.AskInPlace = { [weak self] plan in await self?.askInPlace(job, plan: plan) ?? false }
        let markInPlace: @Sendable () async -> Void = { [weak self] in await self?.markInPlace(job.id) }
        let task = Task { [weak self] in
            do {
                let placed = try await extractor.extract(job, askInPlace: ask, onInPlace: markInPlace)
                self?.finish(job, placed: placed, failure: nil)
            } catch is CancellationError {
                await self?.stopped(job, failure: nil, extractor: extractor)
            } catch {
                let failure = error as? ArchiveFailure ?? .failed(error.localizedDescription)
                await self?.stopped(job, failure: failure, extractor: extractor)
            }
        }
        current = (job, task)
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: "archivebox",
                         text: String(localized: "Extracting \(job.name)", table: "NotchcastArchives"),
                         progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.confirmCancel(job) })
    }

    /// A stop or failure discards or salvages the job; after a module stop it stays to resume.
    private func stopped(_ job: ArchiveJob, failure: ArchiveFailure?, extractor: ArchiveExtractor) async {
        guard current?.job.id == job.id else { return }
        let salvaged = await extractor.abandon(latest(job))
        finish(job, placed: salvaged, failure: failure, cancelled: failure == nil)
    }

    private func finish(_ job: ArchiveJob, placed: URL?, failure: ArchiveFailure?, cancelled: Bool = false) {
        guard current?.job.id == job.id else { return }
        current = nil
        jobs.removeAll { $0.id == job.id }
        save()
        context.presenter.end(notice: Self.noticeID)
        if let failure {
            report(failure, salvaged: placed)
        } else if cancelled {
            post(String(localized: "Stopped extracting \(job.name)", table: "NotchcastArchives"),
                 symbol: "xmark.circle", reveal: placed)
        } else if let placed {
            post(String(localized: "Extracted \(placed.lastPathComponent)", table: "NotchcastArchives"),
                 symbol: "checkmark.circle", reveal: placed)
        } else {
            post(String(localized: "\(job.name) is empty", table: "NotchcastArchives"), symbol: "archivebox", reveal: nil)
        }
        runNext()
    }

    private func report(_ failure: ArchiveFailure, salvaged: URL? = nil) {
        context.presenter.post(
            IslandNotice(id: "archives.failed", symbol: "exclamationmark.triangle", text: failure.message, isFailure: true),
            onTap: revealing(salvaged))
    }

    private func post(_ text: String, symbol: String, reveal url: URL?) {
        context.presenter.post(
            IslandNotice(id: "archives.done", symbol: symbol, text: text),
            onTap: revealing(url))
    }

    private func revealing(_ url: URL?) -> (@MainActor () -> Void)? {
        guard let url else { return nil }
        return { [weak self] in self?.environment.reveal(url) }
    }

    private func confirmCancel(_ job: ArchiveJob) {
        guard let confirm = context.confirm else { return cancel(job.id) }
        Task {
            let title = String(localized: "Stop extracting \(job.name)?", table: "NotchcastArchives")
            let message = String(
                localized: "A kept archive stays as it was. One extracted in place keeps what is already out.",
                table: "NotchcastArchives")
            guard await confirm(title, message, String(localized: "Stop", table: "NotchcastArchives")) else { return }
            cancel(job.id)
        }
    }

    private func askInPlace(_ job: ArchiveJob, plan: String) async -> Bool {
        guard current?.job.id == job.id, let confirm = context.confirm else { return false }
        let title = String(localized: "Not enough space to keep \(job.name)", table: "NotchcastArchives")
        let message = String(
            localized: "Extract in place instead? The archive is removed as its files come out.\n\n\(plan)",
            table: "NotchcastArchives")
        return await confirm(title, message, String(localized: "Extract in Place", table: "NotchcastArchives"))
    }

    private func markInPlace(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].inPlace = true
        save()
    }

    /// The journal's copy, which knows whether the user switched it to in place.
    private func latest(_ job: ArchiveJob) -> ArchiveJob { jobs.first { $0.id == job.id } ?? job }

    private func save() {
        let folder = environment.journal.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? ArchiveJob.encode(jobs).write(to: environment.journal, options: .atomic)
    }
}
