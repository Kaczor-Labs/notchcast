import Foundation

/// One recording at a time, from the Record command through the island's stop control to the trimmer.
@MainActor
final class ScreenRecordingModule: NotchcastModule {
    static let switchID = ScreenRecordingAddon.switches[0].id
    static let islandID = "recording"

    private let context: NotchcastContext
    private let system: RecordingSystem
    private let timeZone: TimeZone
    private(set) var state = RecordingState()
    private var running = false
    /// The recording in hand; a callback or task for an older one finds it changed and stands down.
    private var operation: UUID?
    private var options = RecordingOptions()
    private var startedAt = Date.distantPast
    private var capture: (any RecordingCapture)?
    private var clip: URL?
    private var capturing: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var closeSurface: (@MainActor () -> Void)?
    private var closeTrimmer: (@MainActor () -> Void)?
    private var stopTicking: (@MainActor () -> Void)?
    private var allowSleep: (@MainActor () -> Void)?
    private var diskCheck: Task<Void, Never>?
    private var endedWhileStarting: UUID?

    init(context: NotchcastContext, system: RecordingSystem, timeZone: TimeZone = .current) {
        self.context = context
        self.system = system
        self.timeZone = timeZone
    }

    func start() { running = true }

    /// A clip already recorded is never lost: it is saved as it is, untrimmed.
    func stop() {
        running = false
        operation = nil
        let (capture, clip, options, date) = (capture, clip, options, startedAt)
        self.capture = nil
        self.clip = nil
        closeSurface?()
        closeSurface = nil
        closeTrimmer?()
        closeTrimmer = nil
        hideRecording()
        state.reset()
        guard let clip else { return }
        let previous = capturing
        enqueue {
            await previous?.value
            try? await capture?.stop()
            try await self.output(clip, nil, options, date: date, saving: true)
        }
    }

    func record(_ kind: RecordingKind) {
        guard running else { return }
        switch state.command(kind) {
        case .ignore: return
        case .stop: finishRecording()
        case .select(let kind):
            guard system.grantScreen() else { return fail(RecordingTarget.Failure.screenPermission) }
            let id = UUID()
            operation = id
            closeSurface = system.select(kind) { [weak self] target in
                guard let self, operation == id else { return }
                closeSurface = nil
                guard state.selected(target != nil), let target else {
                    operation = nil
                    return
                }
                begin(target, id)
            }
        case .startScreen:
            guard system.grantScreen() else { return fail(RecordingTarget.Failure.screenPermission) }
            guard let display = system.displayUnderCursor() else {
                return fail(RecordingTarget.Failure.targetUnavailable)
            }
            let id = UUID()
            operation = id
            begin(.display(display), id)
        }
    }

    /// Waits out the capture and export in hand, so a harness never sleeps.
    func settled() async {
        await diskCheck?.value
        await capturing?.value
        await saving?.value
    }

    /// The island's stop control and its menu row.
    func stopRecording() {
        guard state.stopRequested() else { return }
        finishRecording()
    }

    private func begin(_ target: RecordingTarget, _ id: UUID) {
        let options = RecordingOptions(context.defaults)
        capturing = Task {
            var file: URL?
            do {
                if options.microphone, !(await system.grantMicrophone()) {
                    throw RecordingTarget.Failure.microphonePermission
                }
                guard RecordingDisk.canStart(freeBytes: await system.freeBytes()) else {
                    throw RecordingTarget.Failure.diskFull
                }
                guard operation == id else { return }
                let url = try system.workFolder().appending(path: "\(id.uuidString).mov")
                file = url
                let capture = try await system.start(target, options, url) { [weak self] _ in self?.ended(id) }
                guard operation == id, state.started(at: context.now()) else {
                    try? await capture.stop()
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.capture = capture
                self.options = options
                clip = url
                startedAt = context.now()
                showRecording()
                if endedWhileStarting == id { stopRecording() }
            } catch {
                if let file { try? FileManager.default.removeItem(at: file) }
                guard operation == id else { return }
                fail(error)
            }
        }
    }

    /// The capture stopped by itself (its window closed, sharing was stopped): keep what it recorded.
    private func ended(_ id: UUID) {
        guard operation == id else { return }
        if state.phase == .starting { endedWhileStarting = id }
        stopRecording()
    }

    private func finishRecording() {
        hideRecording()
        guard let id = operation, let capture, let clip else { return state.reset() }
        self.capture = nil
        capturing = Task {
            do {
                var stopFailure: (any Error)?
                do { try await capture.stop() } catch { stopFailure = error }
                let duration = (try? await system.duration(clip)) ?? 0
                guard duration > 0 else { throw stopFailure ?? RecordingTarget.Failure.emptyRecording }
                guard operation == id, state.finished() else { return }
                closeTrimmer = system.trim(clip, duration) { [weak self] answer in self?.answer(answer, id) }
            } catch {
                guard operation == id else { return }
                self.clip = nil
                try? FileManager.default.removeItem(at: clip)
                fail(error)
            }
        }
    }

    private func answer(_ answer: RecordingTrimmerAnswer, _ id: UUID) {
        guard operation == id, let clip else { return }
        let (options, date) = (options, startedAt)
        operation = nil
        closeTrimmer = nil
        self.clip = nil
        state.reset()
        switch answer {
        case .discard:
            try? FileManager.default.removeItem(at: clip)
        case .save(let trim):
            enqueue { try await self.output(clip, trim, options, date: date, saving: true) }
        case .copy(let trim):
            enqueue { try await self.output(clip, trim, options, date: date, saving: false) }
        }
    }

    /// Exports one after another, so a switch-off save never races the export before it.
    private func enqueue(_ work: @escaping @MainActor () async throws -> Void) {
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await work()
            } catch {
                fail(error, resetting: false)
            }
        }
    }

    /// A nil trim keeps the clip whole.
    private func output(_ clip: URL, _ trim: RecordingTrim?, _ options: RecordingOptions, date: Date,
                        saving: Bool) async throws {
        context.presenter.post(IslandNotice(
            id: Self.islandID, symbol: "record.circle",
            text: String(localized: "Saving Recording…", table: "NotchcastScreenRecording"),
            progress: IslandProgress(fraction: nil, headline: false)), onTap: nil)
        let folder = try saving
            ? options.folder.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? system.desktop()
            : system.workFolder()
        if saving { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var plan = RecordingExport.copy
        let trim = trim ?? RecordingTrim(duration: 0)
        if !trim.isWhole || options.container != .mov {
            plan = .plan(trim, container: options.container,
                         passthroughWorks: await system.passthroughWorks(clip, options.container))
        }
        let destination = RecordingRescue.freeName(
            in: folder, date: date, timeZone: timeZone, fileExtension: options.container.fileExtension)
        do {
            try await system.export(clip, trim, plan, destination)
        } catch {
            let desktop = [(try? system.desktop())].compactMap { $0 }
            guard let kept = await RecordingRescue.keep(clip, in: desktop, date: date, timeZone: timeZone)
            else { throw RecordingTarget.Failure.exportFailed }
            context.presenter.post(IslandNotice(
                id: Self.islandID, symbol: "record.circle",
                text: String(localized: "Export failed, so the whole recording is on the Desktop.",
                             table: "NotchcastScreenRecording"),
                isFailure: true), onTap: { [system] in system.reveal(kept) })
            return
        }
        try? FileManager.default.removeItem(at: clip)
        if saving {
            context.presenter.post(IslandNotice(
                id: Self.islandID, symbol: "checkmark.circle",
                text: String(localized: "Recording Saved", table: "NotchcastScreenRecording")),
                onTap: { [system] in system.reveal(destination) })
        } else {
            guard system.writeClipboard(destination) else { throw RecordingTarget.Failure.clipboardFailed }
            context.presenter.post(IslandNotice(
                id: Self.islandID, symbol: "checkmark.circle",
                text: String(localized: "Recording Copied", table: "NotchcastScreenRecording")), onTap: nil)
        }
    }

    private func showRecording() {
        refreshStatus()
        allowSleep = system.keepAwake()
        stopTicking = system.everySecond { [weak self] in
            self?.refreshStatus()
            self?.checkDisk()
        }
        let row = IslandMenuRow(id: "stop", title: Self.stopTitle)
        context.presenter.setMenuRows([row], owner: Self.islandID) { [weak self] _ in self?.stopRecording() }
    }

    private func refreshStatus() {
        guard let elapsed = state.elapsed(at: context.now()) else { return }
        context.presenter.setStatus(
            IslandStatus(id: Self.islandID, symbol: "stop.circle", text: RecordingClock.text(elapsed),
                         label: Self.stopTitle),
            for: Self.islandID, onTap: { [weak self] in self?.stopRecording() })
    }

    /// Asking for free space is slow, so only the decision to stop comes back to the main actor.
    private func checkDisk() {
        guard diskCheck == nil, let id = operation else { return }
        diskCheck = Task {
            let free = await system.freeBytes()
            diskCheck = nil
            guard operation == id, RecordingDisk.shouldStop(freeBytes: free), state.stopRequested() else { return }
            context.presenter.post(IslandNotice(
                id: Self.islandID, symbol: "externaldrive.badge.exclamationmark",
                text: String(localized: "Recording stopped: the disk is almost full.", table: "NotchcastScreenRecording"),
                isFailure: true), onTap: nil)
            finishRecording()
        }
    }

    private func hideRecording() {
        stopTicking?()
        stopTicking = nil
        allowSleep?()
        allowSleep = nil
        context.presenter.setStatus(nil, for: Self.islandID, onTap: nil)
        context.presenter.setMenuRows([], owner: Self.islandID) { _ in }
    }

    private func fail(_ error: any Error, resetting: Bool = true) {
        if resetting {
            operation = nil
            state.reset()
        }
        context.presenter.post(IslandNotice(
            id: Self.islandID, symbol: "record.circle", text: RecordingTarget.failureMessage(error), isFailure: true),
            onTap: nil)
    }

    private static var stopTitle: String { String(localized: "Stop Recording", table: "NotchcastScreenRecording") }
}
