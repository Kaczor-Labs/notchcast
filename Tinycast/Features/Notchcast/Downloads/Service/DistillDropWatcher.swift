import CoreServices
import Foundation

/// Queues files dropped into the Markdown folder for Distill while Convert dropped files is on.
@MainActor
final class DistillDropWatcher {
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let distill: DownloadsQueueController
    private var folder: URL?
    private var stream: FileSystemWatcher?
    private var observer: NotificationToken?
    private var recheck: Task<Void, Never>?

    init(defaults: UserDefaults, now: @escaping @MainActor () -> Date, distill: DownloadsQueueController) {
        self.defaults = defaults
        self.now = now
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
        Task { [weak self] in
            let entries = await Self.entries(in: folder)
            guard let self, self.folder == folder, let queue = distill.queue else { return done(0) }
            let plan = DistillDrop.plan(entries, jobs: queue.jobs, now: now(), retryFailed: retryFailed)
            if !plan.sources.isEmpty { _ = distill.accept(kind: DistillRunner.kind, sources: plan.sources) }
            schedule(plan.recheck)
            done(plan.sources.count)
        }
    }

    /// Any change in the suite lands here; only a new folder, or the option going off, restarts the watch.
    private func follow() {
        let wanted = defaults.bool(forKey: DistillNotes.convertKey) ? DistillNotes.folder(in: defaults) : nil
        guard wanted != folder else { return }
        watch(wanted)
    }

    private func watch(_ target: URL?) {
        folder = target
        stream = nil
        recheck?.cancel()
        recheck = nil
        guard let target else { return }
        stream = FileSystemWatcher(
            paths: [target.path(percentEncoded: false)], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rescan() }
        }
        rescan()
    }

    private func schedule(_ date: Date?) {
        recheck?.cancel()
        recheck = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now()))
        recheck = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(delay))) != nil else { return }
            self?.rescan()
        }
    }

    @concurrent
    private static func entries(in folder: URL) async -> [DistillDrop.Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return DistillDrop.Entry(
                path: url.path(percentEncoded: false), isRegularFile: values.isRegularFile == true,
                isSymbolicLink: values.isSymbolicLink == true, modified: values.contentModificationDate ?? .distantPast)
        }
    }
}
