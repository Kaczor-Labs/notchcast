import Foundation

/// Extracts opened archives from a journalled queue; compresses a Finder selection, one at a time.
@MainActor
final class ArchivesModule: NotchcastModule {
    static let switchID = "archives"
    static let defaultAppKey = "archivesDefaultApp"
    static let inPlaceKey = "archivesInPlace"
    /// Set once the archive types were claimed, so a later launch leaves the user's Finder choice alone.
    private static let claimedKey = "archivesClaimed"
    private static let noticeID = "archives.extracting"
    private static let resultNoticeID = "archives.extractionResult"
    private static let compressNoticeID = "archives.compressing"

    private let context: NotchcastContext
    private let environment: ArchivesEnvironment
    private var picker: Task<Void, Never>?
    private(set) var jobs: [ArchiveJob] = []
    private(set) var current: (job: ArchiveJob, task: Task<Void, Never>, resuming: UUID?, question: Task<Void, Never>?)?
    private var pruning: Task<Void, Never>?
    private var isRunning = false
    private var interruptedForSwitch = false
    /// `label` is nil while Finder's selection is still being read.
    private(set) var compression: (id: UUID, label: String?, task: Task<Void, Never>, question: Task<Void, Never>?)?

    init(context: NotchcastContext, environment: ArchivesEnvironment) {
        self.context = context
        self.environment = environment
    }

    var hasPendingQuestion: Bool {
        context.askSecret != nil && jobs.contains { $0.stopped == nil && $0.needsPassword == true }
    }

    func start() {
        isRunning = true
        if current == nil {
            jobs = environment.loadJournal()
            pruneStoppedJobs()
        }
        context.handleOpenURL { [weak self] url in
            guard let self, url.isFileURL, ArchiveRoute(fileName: url.lastPathComponent) != nil else { return false }
            open([url])
            return true
        }
        if context.defaults.bool(forKey: Self.defaultAppKey), !context.defaults.bool(forKey: Self.claimedKey) {
            setDefaultApp(true)
        }
        runNext()
    }

    /// A switch turned off gives the archive types back; quitting the app keeps them.
    func stop() {
        isRunning = false
        picker?.cancel()
        picker = nil
        let switchedOff = !context.isEnabled(Self.switchID)
        if switchedOff, context.defaults.bool(forKey: Self.defaultAppKey) {
            setDefaultApp(false)
        }
        pruning?.cancel()
        pruning = nil
        if switchedOff, let current {
            if !current.task.isCancelled { interruptedForSwitch = true }
            context.recovery(ArchivesAddon.Recovery.self)?.stopping = self
        }
        current?.task.cancel()
        current?.question?.cancel()
        if !switchedOff && !interruptedForSwitch { current = nil }
        context.presenter.end(notice: Self.noticeID)
        compression?.task.cancel()
        compression?.question?.cancel()
        compression = nil
        context.presenter.end(notice: Self.compressNoticeID)
    }

    func open(_ urls: [URL]) {
        for url in urls {
            guard ArchiveRoute(fileName: url.lastPathComponent) != nil else {
                report(.notArchive(url.lastPathComponent))
                continue
            }
            guard !jobs.contains(where: { $0.archive.path == url.path && $0.stopped == nil }) else { continue }
            jobs.append(ArchiveJob(id: UUID(), archive: url, inPlace: context.defaults.bool(forKey: Self.inPlaceKey)))
        }
        environment.saveJournal(jobs)
        runNext()
    }

    func pickAndOpen() {
        guard picker == nil else { return }
        picker = Task { [weak self, pick = environment.pickArchives] in
            let files = await pick()
            guard let self, !Task.isCancelled else { return }
            self.picker = nil
            self.open(files)
        }
    }

    func setDefaultApp(_ on: Bool) {
        context.defaults.set(on, forKey: Self.claimedKey)
        environment.setDefaultApp(on)
    }

    func cancel(_ id: UUID) {
        if current?.job.id == id {
            current?.task.cancel()
        } else {
            jobs.removeAll { $0.id == id && $0.stopped == nil }
            environment.saveJournal(jobs)
        }
    }

    func cancelAll() {
        let running = current?.job.id
        // A stopped entry holds the only path its archive can still be extracted into.
        jobs.removeAll { $0.id != running && $0.stopped == nil }
        environment.saveJournal(jobs)
        if let running { cancel(running) }
    }

    /// Waits for the queue to empty; the harness's only clock.
    func drain() async {
        while let task = pruning ?? current?.task { await task.value }
    }

    func drainCompression() async {
        while let task = compression?.task { await task.value }
    }

    /// Compresses Finder's selection into one archive beside it; extraction's queue runs on meanwhile.
    func compress(_ format: ArchiveFormat) {
        if let compression {
            // While the selection is still being read, a second press is the same request.
            if let label = compression.label { report(.busy(label)) }
            return
        }
        let id = UUID()
        let (readSelection, compressor) = (environment.finderSelection, environment.compressor)
        let task = Task { [weak self] in
            var label: String?
            do {
                let plan = try ArchiveCompression.plan(
                    format: format, selection: try await readSelection(), kind: ArchiveCompressor.kind,
                    isWritable: ArchiveCompressor.isWritable)
                try Task.checkCancellation()
                label = plan.label
                self?.compressionBegan(id, label: plan.label)
                let made = try await compressor.compress(plan)
                self?.compressionEnded(id, made: made)
            } catch is CancellationError {
                self?.compressionEnded(id, stopped: label)
            } catch {
                self?.compressionEnded(id, failure: error as? ArchiveFailure ?? .compressionFailed(error.localizedDescription))
            }
        }
        compression = (id, nil, task, nil)
    }

    private func compressionBegan(_ id: UUID, label: String) {
        guard compression?.id == id else { return }
        compression?.label = label
        context.presenter.post(
            IslandNotice(id: Self.compressNoticeID, symbol: "doc.zipper",
                         text: String(localized: "Compressing \(label)", table: "NotchcastArchives"),
                         progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.confirmStopCompression(id, label: label) })
    }

    private func compressionEnded(_ id: UUID, made: URL? = nil, failure: ArchiveFailure? = nil, stopped: String? = nil) {
        guard compression?.id == id else { return }
        compression?.question?.cancel()
        compression = nil
        context.presenter.end(notice: Self.compressNoticeID)
        if let failure {
            report(failure)
        } else if let made {
            post(String(localized: "Compressed \(made.lastPathComponent)", table: "NotchcastArchives"),
                 symbol: "checkmark.circle", reveal: made)
        } else if let stopped {
            post(String(localized: "Stopped compressing \(stopped)", table: "NotchcastArchives"),
                 symbol: "xmark.circle", reveal: nil)
        }
    }

    private func confirmStopCompression(_ id: UUID, label: String) {
        guard let confirm = context.confirm else {
            if compression?.id == id { compression?.task.cancel() }
            return
        }
        guard compression?.id == id, compression?.question == nil else { return }
        compression?.question = Task { [weak self] in
            let title = String(localized: "Stop compressing \(label)?", table: "NotchcastArchives")
            let message = String(
                localized: "Nothing is kept. The selected files stay as they are.", table: "NotchcastArchives")
            let stop = await confirm(title, message, String(localized: "Stop", table: "NotchcastArchives"))
            guard let self, compression?.id == id else { return }
            compression?.question = nil
            if stop { compression?.task.cancel() }
        }
    }

    private func pruneStoppedJobs() {
        let cutoff = context.now().addingTimeInterval(-7 * 24 * 60 * 60)
        let candidates = jobs.filter { job in
            guard let stoppedAt = job.stopped?.stoppedAt else { return false }
            return stoppedAt < cutoff
        }
        guard !candidates.isEmpty else { return }
        pruning = Task { [weak self] in
            for job in candidates {
                let removed = await ArchiveExtractor.pruneStaging(for: job)
                guard !Task.isCancelled, let self else { return }
                if removed {
                    jobs.removeAll { $0.id == job.id }
                    environment.saveJournal(jobs)
                }
            }
            self?.pruning = nil
            self?.runNext()
        }
    }

    private func resumeStaging(_ job: ArchiveJob, reportedPath: String?) async -> URL? {
        guard current?.job.id == job.id, !Task.isCancelled,
            let entry = ArchiveExtractor.stoppedEntry(for: job, reportedPath: reportedPath, in: jobs)
        else { return nil }
        if !FileManager.default.fileExists(atPath: job.archive.path + ".hatchzip") {
            if await ArchiveExtractor.removeStaging(for: entry), current?.job.id == job.id, !Task.isCancelled {
                jobs.removeAll { $0.id == entry.id }
                environment.saveJournal(jobs)
            }
            return nil
        }
        current?.resuming = entry.id
        return entry.staging
    }

    private func runNext() {
        guard isRunning, context.isEnabled(Self.switchID), pruning == nil, current == nil,
            let job = jobs.first(where: { $0.stopped == nil })
        else { return }
        let extractor = environment.extractor
        let ask: ArchiveExtractor.AskInPlace = { [weak self] plan in await self?.askInPlace(job, plan: plan) ?? false }
        let password: ArchiveExtractor.AskPassword = { [weak self] wrong in await self?.askPassword(job, wrong: wrong) }
        let askPassword = context.askSecret == nil ? nil : password
        let markInPlace: @Sendable (Bool) async -> Void = { [weak self] on in await self?.markInPlace(job.id, on) }
        let task = Task { [self] in
            do {
                let staged = try await extractor.extract(
                    job, askPassword: askPassword, askInPlace: ask, onInPlace: markInPlace,
                    resumeStaging: { [weak self] path in await self?.resumeStaging(job, reportedPath: path) })
                guard current?.job.id == job.id else { return }
                try Task.checkCancellation()
                interruptedForSwitch = !context.isEnabled(Self.switchID)
                guard !interruptedForSwitch else { throw CancellationError() }
                let placed = try extractor.place(staged.job, stem: staged.stem)
                finish(job, placed: placed, failure: nil)
            } catch {
                let failure = Task.isCancelled || error is CancellationError
                    ? nil : error as? ArchiveFailure ?? .failed(error.localizedDescription)
                await stopped(job, failure: failure, extractor: extractor)
            }
        }
        current = (job, task, nil, nil)
        context.presenter.end(notice: Self.resultNoticeID)
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: "archivebox",
                         text: String(localized: "Extracting \(job.name)", table: "NotchcastArchives"),
                         progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.confirmCancel(job) })
    }

    private func stopped(_ job: ArchiveJob, failure: ArchiveFailure?, extractor: ArchiveExtractor) async {
        guard current?.job.id == job.id else { return }
        switch failure {
        case .startedElsewhere, .resumeJournalMismatch:
            finish(job, placed: nil, failure: failure)
            return
        default: break
        }
        if current?.resuming != nil {
            finish(job, placed: nil, failure: failure, cancelled: failure == nil)
            return
        }
        let job = latest(job)
        // A fresh task: this one is cancelled after a stop, which would refuse `hatchzip restore`.
        let left = await Task { await extractor.abandon(job) }.value
        finish(job, placed: left.placed, failure: failure, cancelled: failure == nil, stoppedSize: left.stoppedSize)
    }

    private func finish(
        _ job: ArchiveJob, placed: URL?, failure: ArchiveFailure?, cancelled: Bool = false,
        stoppedSize: Int64? = nil
    ) {
        guard current?.job.id == job.id else { return }
        let resuming = current?.resuming
        let index = jobs.firstIndex(where: { $0.id == job.id })
        if let index, let stoppedSize {
            jobs[index].stopped = ArchiveFingerprint(size: stoppedSize, stoppedAt: context.now())
        } else if interruptedForSwitch, cancelled, !job.inPlace, resuming == nil, let index {
            var retry = ArchiveJob(id: UUID(), archive: job.archive, inPlace: false)
            retry.needsPassword = job.needsPassword
            jobs[index] = retry
        } else {
            let resumed = failure == nil && !cancelled ? resuming : nil
            jobs.removeAll { $0.id == job.id || $0.id == resumed }
        }
        current?.question?.cancel()
        current = nil
        interruptedForSwitch = false
        context.recovery(ArchivesAddon.Recovery.self)?.stopping = nil
        environment.saveJournal(jobs)
        context.presenter.end(notice: Self.noticeID)
        if let failure {
            report(failure, salvaged: placed)
        } else if cancelled {
            post(String(localized: "Stopped extracting \(job.name)", table: "NotchcastArchives"),
                 id: Self.resultNoticeID, symbol: "xmark.circle", reveal: placed)
        } else if let placed {
            post(String(localized: "Extracted \(placed.lastPathComponent)", table: "NotchcastArchives"),
                 id: Self.resultNoticeID, symbol: "checkmark.circle", reveal: placed)
        } else {
            post(String(localized: "\(job.name) is empty", table: "NotchcastArchives"),
                 id: Self.resultNoticeID, symbol: "archivebox", reveal: nil)
        }
        runNext()
    }

    private func report(_ failure: ArchiveFailure, salvaged: URL? = nil) {
        context.presenter.post(
            IslandNotice(id: "archives.failed", symbol: "exclamationmark.triangle", text: failure.message, isFailure: true),
            onTap: revealing(salvaged))
    }

    private func post(_ text: String, id: String = "archives.done", symbol: String, reveal url: URL?) {
        context.presenter.post(
            IslandNotice(id: id, symbol: symbol, text: text),
            onTap: revealing(url))
    }

    private func revealing(_ url: URL?) -> (@MainActor () -> Void)? {
        guard let url else { return nil }
        return { [weak self] in self?.environment.reveal(url) }
    }

    private func confirmCancel(_ job: ArchiveJob) {
        guard let confirm = context.confirm else { return cancel(job.id) }
        guard current?.job.id == job.id, current?.question == nil else { return }
        current?.question = Task { [weak self] in
            let title = String(localized: "Stop extracting \(job.name)?", table: "NotchcastArchives")
            let message = String(
                localized: "A kept archive stays as it was. One extracted in place keeps what is already out.",
                table: "NotchcastArchives")
            let stop = await confirm(title, message, String(localized: "Stop", table: "NotchcastArchives"))
            guard let self, current?.job.id == job.id else { return }
            current?.question = nil
            if stop { cancel(job.id) }
        }
    }

    private func askInPlace(_ job: ArchiveJob, plan: String) async -> Bool {
        guard !Task.isCancelled, current?.job.id == job.id, let confirm = context.confirm else { return false }
        let title = String(localized: "Not enough space to keep \(job.name)", table: "NotchcastArchives")
        let message = String(
            localized: "Extract in place instead? The archive is removed as its files come out.\n\n\(plan)",
            table: "NotchcastArchives")
        return await confirm(title, message, String(localized: "Extract in Place", table: "NotchcastArchives"))
    }

    /// Hands the answer straight back to the extractor; the module never keeps it.
    private func askPassword(_ job: ArchiveJob, wrong: Bool) async -> String? {
        guard !Task.isCancelled, current?.job.id == job.id, let askSecret = context.askSecret,
            let index = jobs.firstIndex(where: { $0.id == job.id })
        else { return nil }
        if jobs[index].needsPassword != true {
            jobs[index].needsPassword = true
            environment.saveJournal(jobs)
        }
        return await NotchcastQuestion.$takesLauncherPriority.withValue(true) {
            await askSecret(
                String(localized: "Password for \(job.name)", table: "NotchcastArchives"),
                wrong ? String(localized: "That password did not work.", table: "NotchcastArchives") : nil,
                String(localized: "Password", table: "NotchcastArchives"),
                String(localized: "Extract", table: "NotchcastArchives"))
        }
    }

    private func markInPlace(_ id: UUID, _ on: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].inPlace = on
        environment.saveJournal(jobs)
    }

    /// The journal's copy, which knows whether the user switched it to in place.
    private func latest(_ job: ArchiveJob) -> ArchiveJob { jobs.first { $0.id == job.id } ?? job }
}
