// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tinycast/Platform/Permissions.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift Tinycast/Platform/CameraAccess.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Dispatch
import Synchronization

private enum CleanerScanTask {
    @TaskLocal static var first = false
}

// The fake parks the first scan's thread, so it must not be the strict cooperative pool's only one.
private final class CleanerParkedScanExecutor: TaskExecutor {
    private let queue = DispatchQueue(label: "nc-Cleaner-session-test.first-scan")

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}

@main
@MainActor
struct CleanerSessionTest {
    static func main() async {
        await checksAccessAndConfirmation()
        await checksCancellationAndReopen()
    }

    private static func checksAccessAndConfirmation() async {
        let fs = CleanerTestFileSystem()
        let item = CleanerTestFileSystem.item("org.example.cache")
        fs.put(item, size: 64)
        var hasAccess = false
        let session = CleanerSession(
            home: CleanerTestFileSystem.area.home, runner: CleanerRunner(scanner: fs.scanner, runningApps: { .init() }),
            hasAccess: { hasAccess })

        await session.open()
        precondition(session.phase == .needsAccess && fs.reads == 0)
        hasAccess = true
        await session.open()
        precondition(session.phase == .review && session.selection?.checked == [item])

        await session.clean { selection in
            precondition(selection.checked == [item])
            return false
        }
        precondition(session.phase == .review && fs.trashCalls.isEmpty)

        hasAccess = false
        await session.clean { _ in true }
        precondition(session.phase == .needsAccess && fs.trashCalls.isEmpty)

        hasAccess = true
        await session.open()
        await session.clean { _ in true }
        precondition(session.phase == .done && session.report?.knownMovedBytes == 64)
        precondition(fs.trashCalls == [item])
    }

    private static func checksCancellationAndReopen() async {
        let releaseFirstScan = DispatchSemaphore(value: 0)
        let started = Mutex(false)
        let (starts, signalStart) = AsyncStream<Void>.makeStream()
        let fs = CleanerTestFileSystem { url in
            guard CleanerScanTask.first, url.path == "/" else { return }
            let isFirstInspection = started.withLock { started in
                let wasStarted = started
                started = true
                return !wasStarted
            }
            guard isFirstInspection else { return }
            signalStart.yield(())
            releaseFirstScan.wait()
        }
        let item = CleanerTestFileSystem.item("org.example.reopened")
        fs.put(item, size: 32)
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: {
            if !CleanerScanTask.first { releaseFirstScan.signal() }
            return .init()
        })
        let session = CleanerSession(home: CleanerTestFileSystem.area.home, runner: runner, hasAccess: { true })
        let first = Task(executorPreference: CleanerParkedScanExecutor()) {
            await CleanerScanTask.$first.withValue(true) { await session.open() }
        }

        var events = starts.makeAsyncIterator()
        _ = await events.next()
        first.cancel()
        await session.open()
        await first.value
        signalStart.finish()

        precondition(session.phase == .review && session.items.map(\.id) == [item])
        precondition(session.selection?.checked == [item])

        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await session.open()
        }.value
        precondition(session.phase == .idle && session.items.isEmpty && session.selection == nil)
    }
}
