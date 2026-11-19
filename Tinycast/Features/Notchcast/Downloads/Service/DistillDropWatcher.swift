import CoreServices
import Foundation

/// Queues files that appear in the Markdown folder while Convert dropped files is on, never one already there.
@MainActor
final class DistillDropWatcher {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let sleep: Sleep
    private let distill: DownloadsQueueController
    private(set) var folder: URL?
    private var stream: FileSystemWatcher?
    private var observer: NotificationToken?
    private var recheck: Task<Void, Never>?
    private var scan: Task<Void, Never>?
    private var seen: [String: DistillDrop.Sighting] = [:]
    private var existing: [String: UInt64]?

    init(
        defaults: UserDefaults, now: @escaping @MainActor () -> Date, distill: DownloadsQueueController,
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.distill = distill
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationToken(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.follow() }
        }, center: .default)
        follow()
    }

    func stop() {
        observer = nil
        watch(nil)
    }

    /// Lists the folder off-main, queues each file that is ready and looks again when the next settles.
    /// Run Distill passes `retryFailed`, so only it tries a failed file again.
    func rescan(retryFailed: Bool = false, then done: @escaping @MainActor (_ added: Int) -> Void = { _ in }) {
        guard let folder else { return done(0) }
        let previous = scan
        scan = Task { [weak self] in
            await previous?.value
            let entries = await Self.entries(in: folder)
            guard !Task.isCancelled, let self, self.folder == folder, let queue = distill.queue else { return done(0) }
            // An unlisted folder is not an empty one: forgetting it all makes the next look a first look.
            guard let entries else {
                seen = [:]
                existing = nil
                schedule(nil)
                return done(0)
            }
            let plan = DistillDrop.plan(entries, jobs: queue.jobs, seen: seen, existing: existing, now: now(),
                                        retryFailed: retryFailed)
            seen = plan.seen
            existing = plan.existing
            for entry in plan.ready {
                _ = distill.accept(kind: DistillRunner.kind, sources: [entry.path],
                                   options: try? DownloadJob.encode(entry.stamp))
            }
            schedule(plan.recheck)
            done(plan.ready.count)
        }
    }

    /// Any change in the suite lands here; only a new folder, or the option going off, restarts the watch.
    private func follow() {
        // A change queued just before stop arrives after it, and must not start the watch again.
        guard observer != nil else { return }
        let wanted = DistillNotes.dropFolder(in: defaults)
        if let queue = distill.queue {
            for id in DistillDrop.orphans(queue.jobs, kind: DistillRunner.kind, folder: wanted) { queue.cancel(id) }
        }
        guard wanted != folder else { return }
        watch(wanted)
    }

    private func watch(_ target: URL?) {
        folder = target
        stream = nil
        seen = [:]
        existing = nil
        for task in [recheck, scan] { task?.cancel() }
        recheck = nil
        scan = nil
        guard let target else { return }
        stream = FileSystemWatcher(
            paths: [target.path(percentEncoded: false)], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rescan() }
        }
        // Unwatched, the folder stays unset so the next change in the suite tries again.
        guard stream != nil else {
            folder = nil
            return
        }
        rescan()
    }

    private func schedule(_ date: Date?) {
        recheck?.cancel()
        recheck = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now()))
        recheck = Task { [weak self, sleep] in
            guard (try? await sleep(delay)) != nil else { return }
            self?.rescan()
        }
    }

    @concurrent
    private static func entries(in folder: URL) async -> [DistillDrop.Entry]? {
        let root = folder.path(percentEncoded: false)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        return names.map { name in
            let path = URL(filePath: root).appending(path: name).path(percentEncoded: false)
            return DistillDrop.Entry(path: path, stamp: DistillDrop.stamp(at: path))
        }
    }
}
