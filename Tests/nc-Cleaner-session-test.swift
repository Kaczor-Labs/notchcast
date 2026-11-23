// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tinycast/Platform/Permissions.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift Tinycast/Platform/CameraAccess.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Dispatch

private enum CleanerScanTask {
    @TaskLocal static var first = false
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
            area: CleanerTestFileSystem.area, runner: CleanerRunner(scanner: fs.scanner, runningApps: { .init() }),
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
        let fs = CleanerTestFileSystem { url in
            // Keep the first scan in flight until the next open reaches the session.
            if CleanerScanTask.first, url.path == "/" { releaseFirstScan.wait() }
        }
        let item = CleanerTestFileSystem.item("org.example.reopened")
        fs.put(item, size: 32)
        let (starts, signalStart) = AsyncStream<Void>.makeStream()
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: {
            if CleanerScanTask.first {
                signalStart.yield(())
            } else {
                releaseFirstScan.signal()
            }
            return .init()
        })
        let session = CleanerSession(area: CleanerTestFileSystem.area, runner: runner, hasAccess: { true })
        let first = Task {
            await CleanerScanTask.$first.withValue(true) { await session.open() }
        }

        var events = starts.makeAsyncIterator()
        _ = await events.next()
        first.cancel()
        await session.open()
        releaseFirstScan.signal()
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
