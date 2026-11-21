import Foundation
import Observation

/// Owns the torrent jobs and the one aria2c session they share while any of them is active.
@MainActor
@Observable
final class TorrentManager {
    /// Everything the manager takes from the Mac; the harnesses pass fakes and drive `poll` themselves.
    struct Environment {
        var downloads: URL
        var startSession: @MainActor (_ extraArguments: [String]) async throws -> any TorrentSession = { _ in
            throw TorrentEngineMissing()
        }
        /// A `.torrent` file's bytes, never more than `TorrentMetainfo.maxBytes`.
        var read: @Sendable (TorrentInput) async throws -> Data = { _ in throw CocoaError(.fileReadUnknown) }
        var quarantine: @Sendable ([URL]) -> Void = { _ in }
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        /// Extra aria2c flags read at each session start; Wi-Fi and iPhone bonding plugs in here.
        var extraArguments: @MainActor () -> [String] = { [] }
        var pick: @MainActor () async -> [URL] = { [] }
        var reveal: @MainActor @Sendable ([URL]) -> Void = { _ in }
    }

    enum Outcome: Equatable {
        case queued, nothingUsable, notRunning
    }

    private struct Checked {
        let input: TorrentInput
        let source: TorrentSource
        let infoHash: String
        let name: String
    }

    private(set) var jobs: [TorrentJob] = []
    private(set) var isRunning = false
    let downloads: URL
    @ObservationIgnored let reveal: @MainActor @Sendable ([URL]) -> Void
    @ObservationIgnored let pick: @MainActor () async -> [URL]
    /// The last session stop, so a harness can wait for aria2c to be gone.
    @ObservationIgnored private(set) var stopping: Task<Void, Never>?
    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let keepSharing: @MainActor () -> Bool
    @ObservationIgnored private var session: (any TorrentSession)?
    @ObservationIgnored private var starting: Task<any TorrentSession, any Error>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Bumped at every stop, so work that awaited across one never lands on the next run.
    @ObservationIgnored private var generation = 0

    init(environment: Environment, now: @escaping @MainActor () -> Date, keepSharing: @escaping @MainActor () -> Bool) {
        self.environment = environment
        downloads = environment.downloads
        reveal = environment.reveal
        pick = environment.pick
        self.now = now
        self.keepSharing = keepSharing
    }

    var hasActiveJobs: Bool { jobs.contains { $0.state.isActive } }

    func start() { isRunning = true }

    /// Inputs are refused at once; aria2c is stopped after.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        for index in jobs.indices where jobs[index].state.isActive { finish(index, as: .cancelled) }
        settle()
    }

    /// Checks every input first, then queues the usable ones; a running info hash fails the copy.
    @discardableResult
    func submit(_ inputs: [TorrentInput]) async -> Outcome {
        guard isRunning else { return .notRunning }
        let generation = generation
        var checked: [Checked] = []
        for input in inputs {
            if let item = await check(input) { checked.append(item) }
        }
        guard isRunning, generation == self.generation else { return .notRunning }
        guard !checked.isEmpty else { return .nothingUsable }
        var launches: [(UUID, TorrentSource)] = []
        for item in checked {
            var job = TorrentJob(input: item.input, infoHash: item.infoHash, name: item.name, started: now())
            if jobs.contains(where: { $0.infoHash == item.infoHash && $0.state.isActive }) {
                job.state = .failed(String(localized: "This torrent is already running.", table: "NotchcastDownloads"))
            } else {
                launches.append((job.id, item.source))
            }
            jobs.append(job)
        }
        for (id, source) in launches { await launch(id, source) }
        return .queued
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state.isActive else { return }
        let gid = jobs[index].gid
        finish(index, as: .cancelled)
        if let gid, hasActiveJobs, let session { Task { await session.remove(gid) } }
        settle()
    }

    func cancelAll() {
        for index in jobs.indices where jobs[index].state.isActive { finish(index, as: .cancelled) }
        settle()
    }

    /// Replaces a failed or cancelled row with a fresh job for the same input.
    func retry(_ id: UUID) async -> Outcome {
        guard let job = jobs.first(where: { $0.id == id }), !job.state.isActive else { return .nothingUsable }
        jobs.removeAll { $0.id == id }
        return await submit([job.input])
    }

    func dismiss(_ id: UUID) {
        jobs.removeAll { $0.id == id && !$0.state.isActive }
    }

    /// One look at every active job; the poll loop calls it each second, a harness calls it directly.
    func poll() async {
        guard let session else { return }
        let generation = generation
        guard session.isAlive else {
            let stopped = String(localized: "aria2c stopped.", table: "NotchcastDownloads")
            for index in jobs.indices where jobs[index].state.isActive { finish(index, as: .failed(stopped)) }
            return settle()
        }
        for job in jobs where job.state.isActive {
            guard let gid = job.gid else { continue }
            let status: TorrentStatus
            do {
                status = try await session.status(gid)
            } catch let failure as Aria2Failure {
                guard generation == self.generation, let index = active(job.id, gid: gid) else { continue }
                finish(index, as: .failed(failure.message))
                continue
            } catch {
                continue
            }
            guard generation == self.generation, let index = active(job.id, gid: gid) else { continue }
            let next = TorrentJobPolicy.advance(jobs[index], with: status, now: now(), keepSharing: keepSharing(),
                                                destination: downloads)
            if jobs[index].files.isEmpty, !next.files.isEmpty { environment.quarantine(next.files) }
            jobs[index] = next
            if next.gid != gid || !next.state.isActive { Task { await session.remove(gid) } }
        }
        settle()
    }

    private func check(_ input: TorrentInput) async -> Checked? {
        if case .magnet(let link) = input {
            guard let magnet = TorrentMagnet(link) else { return nil }
            return Checked(input: input, source: .magnet(link), infoHash: magnet.infoHash,
                           name: magnet.name ?? magnet.infoHash)
        }
        guard let data = try? await environment.read(input), let metainfo = TorrentMetainfo(data: data) else {
            return nil
        }
        return Checked(input: input, source: .torrent(metainfo.data), infoHash: metainfo.infoHash, name: metainfo.name)
    }

    private func launch(_ id: UUID, _ source: TorrentSource) async {
        let generation = generation
        do {
            let session = try await engine()
            guard generation == self.generation, let job = jobs.first(where: { $0.id == id }), job.state.isActive
            else { return }
            let gid = try await session.add(source, options: Aria2Arguments.options(keepSharing: keepSharing()))
            guard generation == self.generation, let index = active(id, gid: nil) else {
                return await session.remove(gid)
            }
            jobs[index].gid = gid
            startPolling()
        } catch {
            guard generation == self.generation, let index = active(id, gid: nil) else { return }
            finish(index, as: .failed(error.localizedDescription))
            settle()
        }
    }

    /// The running session, else the one starting, else a new one; a superseded start is stopped.
    private func engine() async throws -> any TorrentSession {
        if let session { return session }
        let task = starting ?? Task { [environment] in try await environment.startSession(environment.extraArguments()) }
        starting = task
        let started = try await task.value
        if session === started { return started }
        if starting == task {
            starting = nil
            session = started
            return started
        }
        stopping = Task { await started.stop() }
        throw CancellationError()
    }

    private func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self, environment] in
            while !Task.isCancelled {
                do { try await environment.sleep(.seconds(1)) } catch { return }
                guard let self else { return }
                await poll()
            }
        }
    }

    /// With no active job left, aria2c goes: Cancel All therefore always ends the process.
    private func settle() {
        guard !hasActiveJobs else { return }
        polling?.cancel()
        polling = nil
        starting?.cancel()
        starting = nil
        guard let session else { return }
        self.session = nil
        let previous = stopping
        stopping = Task {
            await previous?.value
            await session.stop()
        }
    }

    private func finish(_ index: Int, as state: TorrentJob.State) {
        jobs[index].state = state
        jobs[index].speed = 0
    }

    private func active(_ id: UUID, gid: String?) -> Int? {
        jobs.firstIndex { $0.id == id && $0.state.isActive && (gid == nil || $0.gid == gid) }
    }
}
